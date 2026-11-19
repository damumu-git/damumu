using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Muda.Api.Endpoints;
using Muda.Api.Infrastructure;
using Npgsql;

internal static class ScheduleChecks
{
    public static async Task RunAsync()
    {
        var cs = Environment.GetEnvironmentVariable("SCHEDULE_TEST_DATABASE")
            ?? throw new Exception("SCHEDULE_TEST_DATABASE is required");
        var parsed = new NpgsqlConnectionStringBuilder(cs);
        if (parsed.Host != "127.0.0.1" || parsed.Port != 55445 || parsed.Database != "schedule_check")
            throw new Exception("Only the isolated schedule_check database on port 55445 is allowed");
        await using var source = NpgsqlDataSource.Create(cs);
        var db = new Db(source);
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions { EnvironmentName = "Development" });
        builder.WebHost.UseUrls("http://127.0.0.1:0");
        builder.Logging.ClearProviders();
        builder.Configuration["Media:RootPath"] = Path.GetTempPath();
        builder.Configuration["Media:PublicBaseUrl"] = "https://example.invalid/uploads";
        builder.Services.AddSingleton(source);
        builder.Services.AddSingleton(db);
        builder.Services.AddSingleton<MediaStorage>();
        builder.Services.AddSingleton<AuthService>();
        builder.Services.AddSingleton<AccountDeletionService>();
        builder.Configuration["Auth:TokenKey"] = "isolated-schedule-test-signing-key";
        builder.Services.AddSingleton<RealtimeConnectionManager>();
        builder.Services.AddSingleton<PushNotificationService>();
        await using var app = builder.Build();
        app.Use(async (context, next) =>
        {
            try { await next(); }
            catch (ApiException error) { context.Response.StatusCode = error.StatusCode; }
            catch (PostgresException error) when (error.ConstraintName == "event_schedule_conflict")
            { context.Response.StatusCode = 409; }
            catch (Exception error) { Console.WriteLine(error); context.Response.StatusCode = 500; }
        });
        app.MapGroup("/api/v1").MapEventEndpoints();
        app.MapGroup("/api/v1").MapRecurringEventEndpoints();
        app.MapGroup("/api/v1").MapUserEndpoints();
        app.MapGroup("/api/v1").MapActivityEndpoints();
        app.MapGroup("/api/v1").MapWebCommunityEndpoints();
        app.MapGroup("/api/v1").MapSocialEndpoints();
        await app.StartAsync();
        try
        {
            using var http = new HttpClient { BaseAddress = new Uri(app.Urls.Single()) };
            var hosts = Enumerable.Range(0, 4).Select(_ => Guid.NewGuid()).ToArray();
            var member = Guid.NewGuid();
            var second = Guid.NewGuid();
            foreach (var id in hosts.Append(member).Append(second))
                await db.ExecuteAsync("""
                    INSERT INTO app_user(id) VALUES(@id);
                    INSERT INTO user_profile(user_id,nickname,city_code) VALUES(@id,'Fixture','KR-11');
                    """, new { id });
            var category = await db.ScalarAsync<Guid>("SELECT id FROM category WHERE level=2 AND is_active AND NOT requires_custom_label LIMIT 1");
            await db.ExecuteAsync("""
                INSERT INTO member_identity_verification(user_id,provider,verification_reference)
                VALUES(@host,'schedule-test',@host::text);
                """, new { host = hosts[0] });
            var start = DateTime.UtcNow.Date.AddDays(2).AddHours(4);
            CreateEventRequest Request(string title, DateTime at, string mode = "manual",
                string? repeat = null, short? count = null) =>
                new(category, title, "Integration fixture", "KR-11", "KR-11440", at, at.AddHours(2),
                    2, 8, mode, "public", 14, null, 0, 0, "KRW", false, null, null, ["zh"], null,
                    new PlaceRequest("Fixture meeting place", null, null, null), null, null, repeat, count);
            async Task<HttpResponseMessage> Send(Guid user, string path, object payload)
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, path) { Content = JsonContent.Create(payload) };
                request.Headers.Add("X-User-Id", user.ToString());
                return await http.SendAsync(request);
            }
            async Task<JsonElement> Data(HttpResponseMessage response)
            {
                Check(response.IsSuccessStatusCode, "Unexpected HTTP " + response.StatusCode + " " + await response.Content.ReadAsStringAsync());
                return (await response.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("data").Clone();
            }
            async Task<Guid> Create(Guid user, CreateEventRequest input) =>
                (await Data(await Send(user, "/api/v1/events", input))).GetProperty("id").GetGuid();
            async Task<HttpResponseMessage> Get(Guid user, string path)
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, path);
                request.Headers.Add("X-User-Id", user.ToString());
                return await http.SendAsync(request);
            }
            var owner = hosts[0];
            async Task<int> Level(Guid user) => await db.ScalarAsync<int>("SELECT member_level(@user)", new { user });
            Check(await Level(member) == 1 && await Level(owner) == 3, "Ordinary or verified-only level was wrong");
            await db.ExecuteAsync("""
                UPDATE member_identity_verification SET revoked_at=now() WHERE user_id=@owner
                """, new { owner });
            var legacy = await db.QueryAsync("""
                INSERT INTO event(organizer_user_id,category_id,title,description,status,capacity,city_code)
                SELECT @owner,@category,'Reputation fixture','Fixture','published',16,'KR-11'
                FROM generate_series(1,10)
                RETURNING id
                """, new { owner, category });
            var pastIds = legacy.Select(row => (Guid)row["id"]!).ToArray();
            for (var i = 0; i < pastIds.Length; i++)
            {
                var at = start.AddDays(-60-i);
                await db.ExecuteAsync("""
                    INSERT INTO event_schedule(event_id,starts_at,ends_at) VALUES(@eventId,@at,@at+interval '2 hours');
                    INSERT INTO event_member(event_id,user_id,status,checked_in_at) VALUES(@eventId,@member,'attended',@at);
                    """, new { eventId = pastIds[i], at, member });
                if (i == 1) Check(await Level(owner) == 1, "Two successful activities prematurely promoted the host");
                if (i == 2) Check(await Level(owner) == 2, "Three successful activities did not promote the host");
            }
            var lastPastEvent = pastIds[^1];
            pastIds = pastIds[..^1];
            var reviewers = Enumerable.Range(0, 9).Select(_ => Guid.NewGuid()).ToArray();
            await db.ExecuteAsync("""
                INSERT INTO app_user(id) SELECT unnest(@reviewers);
                INSERT INTO event_member(event_id,user_id,status,checked_in_at)
                SELECT s.event_id,r.user_id,'attended',s.starts_at FROM event_schedule s
                CROSS JOIN unnest(@reviewers) AS r(user_id) WHERE s.event_id=ANY(@pastIds);
                INSERT INTO endorsement(context_event_id,from_user_id,target_type,target_id,target_user_id,tag_code)
                SELECT s.event_id,r.user_id,'activity',s.event_id,@owner,'well_organized'
                FROM event_schedule s CROSS JOIN unnest(@reviewers) AS r(user_id) WHERE s.event_id=ANY(@pastIds)
                ORDER BY s.event_id,r.user_id LIMIT 50
                """, new { reviewers, pastIds, owner });
            Check(await Level(owner) == 2, "Exactly 50 activity likes incorrectly qualified for high reputation");
            await db.ExecuteAsync("UPDATE event SET status='cancelled' WHERE id=@lastPastEvent", new { lastPastEvent });
            await db.ExecuteAsync("""
                INSERT INTO endorsement(context_event_id,from_user_id,target_type,target_id,target_user_id,tag_code)
                SELECT s.event_id,r.user_id,'activity',s.event_id,@owner,'well_organized'
                FROM event_schedule s CROSS JOIN unnest(@reviewers) AS r(user_id)
                WHERE s.event_id=ANY(@pastIds) AND NOT EXISTS (
                    SELECT 1 FROM endorsement WHERE context_event_id=s.event_id AND from_user_id=r.user_id)
                LIMIT 1
                """, new { reviewers, pastIds, owner });
            Check(await Level(owner) == 2, "51 likes on nine successful activities prematurely promoted the host");
            await db.ExecuteAsync("UPDATE event SET status='published' WHERE id=@lastPastEvent", new { lastPastEvent });
            Check(await Level(owner) == 3, "Ten successful activities and 51 likes did not qualify for level three");
            await db.ExecuteAsync("UPDATE member_identity_verification SET revoked_at=NULL WHERE user_id=@owner", new { owner });
            Check(await Level(owner) == 4, "Verified high reputation did not reach level four");

            var quotaOwner = Guid.NewGuid();
            await db.ExecuteAsync("INSERT INTO app_user(id) VALUES(@quotaOwner)", new { quotaOwner });
            await Create(quotaOwner, Request("Quota fixture", start.AddDays(19)) with { PriceMin = 3000, PriceMax = 3000 });
            var secondActive = await Create(quotaOwner, Request("Second active fixture", start.AddDays(20)));
            Check((await Send(quotaOwner, "/api/v1/events", Request("Extra active fixture", start.AddDays(21)))).StatusCode
                  == HttpStatusCode.Conflict, "Level one exceeded the two simultaneous activity limit");
            await db.ExecuteAsync("UPDATE event SET status='cancelled' WHERE id=@secondActive", new { secondActive });
            var thirdPublication = await Create(quotaOwner, Request("Third publication fixture", start.AddDays(21)));
            await db.ExecuteAsync("UPDATE event SET status='cancelled' WHERE id=@thirdPublication", new { thirdPublication });
            var fourthPublication = await Create(quotaOwner, Request("Fourth publication fixture", start.AddDays(22)));
            await db.ExecuteAsync("UPDATE event SET status='cancelled' WHERE id=@fourthPublication", new { fourthPublication });
            Check((await Send(quotaOwner, "/api/v1/events", Request("Fifth publication fixture", start.AddDays(23)))).StatusCode
                  == HttpStatusCode.Conflict, "Level one exceeded the four publications per 30 days limit");
            Check((await Send(second, "/api/v1/events", Request("Ordinary repeating fixture", start, repeat: "weekly", count: 2))).StatusCode
                  == HttpStatusCode.Forbidden, "Ordinary member created recurring activities");

            var oversizedGroup = await Send(owner, "/api/v1/web/groups",
                new { title = "Oversized group", description = "Fixture group", capacity = 51 });
            Check(oversizedGroup.StatusCode == HttpStatusCode.BadRequest, "A group accepted capacity above 50");
            var defaultGroup = (await Data(await Send(owner, "/api/v1/web/groups",
                new { title = "Default capacity", description = "Fixture group" }))).GetProperty("id").GetGuid();
            var defaultGroupDetails = await Data(await Get(owner, $"/api/v1/web/groups/{defaultGroup}"));
            Check(defaultGroupDetails.GetProperty("item").GetProperty("capacity").GetInt32() == 50,
                "Older clients omitting capacity did not receive the 50-person default");

            var groupInput = new { title = "Integration group", description = "Fixture group", joinMode = "approval", capacity = 2 };
            Check((await Send(member, "/api/v1/web/groups", groupInput)).StatusCode == HttpStatusCode.Forbidden,
                "Ordinary member created a group");
            var group = (await Data(await Send(owner, "/api/v1/web/groups", groupInput))).GetProperty("id").GetGuid();
            var groupPath = $"/api/v1/web/groups/{group}";
            async Task<HttpResponseMessage> ChangeMembership(Guid user, string path, HttpMethod method)
            {
                using var request = new HttpRequestMessage(method, path);
                request.Headers.Add("X-User-Id", user.ToString());
                return await http.SendAsync(request);
            }
            await Data(await ChangeMembership(member, groupPath+"/membership", HttpMethod.Put));
            await Data(await ChangeMembership(second, groupPath+"/membership", HttpMethod.Put));
            var pendingGroup = await Data(await Get(member, groupPath));
            Check(pendingGroup.GetProperty("item").GetProperty("pending").GetBoolean() &&
                  pendingGroup.GetProperty("applications").GetArrayLength() == 0, "Pending member gained management access");
            await Data(await Send(owner, groupPath+$"/applications/{member}", new { accept = true }));
            Check((await Send(owner, groupPath+$"/applications/{second}", new { accept = true })).StatusCode == HttpStatusCode.Conflict,
                "Owner exceeded group capacity");
            var approvedGroup = await Data(await Get(member, groupPath));
            var conversation = approvedGroup.GetProperty("item").GetProperty("conversation_id").GetGuid();
            var chat = $"/api/v1/conversations/{conversation}/messages";
            Check((await Send(member, groupPath+"/announcements", new { body = "Unauthorized" })).StatusCode == HttpStatusCode.Forbidden,
                "Member published an owner announcement");
            await Data(await Send(owner, groupPath+"/announcements", new { body = "First announcement" }));
            await Data(await Send(owner, groupPath+"/announcements", new { body = "Latest announcement" }));
            Check((await Data(await Get(member, chat))).GetProperty("pinnedAnnouncement").GetString() == "Latest announcement",
                "Chat did not pin the latest announcement");
            await Data(await ChangeMembership(owner, groupPath+$"/members/{member}", HttpMethod.Delete));
            Check((await Get(member, chat)).StatusCode == HttpStatusCode.Forbidden, "Expelled group member retained chat access");
            Console.WriteLine("PASS: four member levels, strict activity likes, publication limits and group membership/announcement authorization");

            var a = await Create(hosts[0], Request("A", start));
            var placeCount = await db.ScalarAsync<long>("SELECT count(*) FROM place");
            Check((await Send(hosts[0], "/api/v1/events", Request("Overlap", start.AddHours(1)))).StatusCode == HttpStatusCode.Conflict,
                "Organizer overlap was accepted");
            Check(placeCount == await db.ScalarAsync<long>("SELECT count(*) FROM place"), "Failed create left an orphan place");
            await Create(hosts[0], Request("Adjacent", start.AddHours(2)));
            var b = await Create(hosts[1], Request("B", start));
            var c = await Create(hosts[2], Request("C", start, "auto"));
            foreach (var eventId in new[] { a, b })
                await Data(await Send(member, $"/api/v1/events/{eventId}/join", new { partySize = 1 }));
            var waitingEvent = await Create(hosts[3], Request("Waiting", start));
            await db.ExecuteAsync("""
                INSERT INTO event_member(event_id,user_id,status,waitlist_position) VALUES(@waitingEvent,@member,'waitlisted',1);
                UPDATE event SET waitlist_count=1 WHERE id=@waitingEvent;
                """, new { waitingEvent, member });
            await Data(await Send(member, $"/api/v1/events/{c}/join", new { partySize = 1 }));
            Check(await db.ScalarAsync<long>("SELECT count(*) FROM event_member WHERE user_id=@member AND status='withdrawn' AND withdrawal_reason='schedule_conflict'", new { member }) == 3,
                "Overlapping pending requests were not withdrawn");
            Check(await db.ScalarAsync<long>("SELECT count(*) FROM notification WHERE user_id=@member AND notification_type='schedule_conflict_withdrawn'", new { member }) == 3,
                "Missing withdrawal notifications");
            Check((await Send(member, $"/api/v1/events/{a}/join", new { partySize = 1 })).StatusCode == HttpStatusCode.Conflict,
                "An overlapping existing commitment allowed another application");

            foreach (var eventId in new[] { a, b })
                await Data(await Send(second, $"/api/v1/events/{eventId}/join", new { partySize = 1 }));
            var decisions = await Task.WhenAll(
                Send(hosts[0], $"/api/v1/events/{a}/members/{second}/approve", new { }),
                Send(hosts[1], $"/api/v1/events/{b}/members/{second}/approve", new { }));
            Check(decisions.All(response => (int)response.StatusCode < 500), "Concurrent approval leaked a server error");
            Check(decisions.Count(response => response.IsSuccessStatusCode) == 1, "Concurrent approvals both succeeded");
            Check(await db.ScalarAsync<long>("SELECT count(*) FROM event_member WHERE user_id=@second AND status='approved'", new { second }) == 1,
                "Concurrent admission produced overlapping commitments");
            Check(await db.ScalarAsync<long>("SELECT count(*) FROM event_member WHERE user_id=@second AND status='withdrawn'", new { second }) == 1,
                "Losing pending request was not withdrawn");

            var recurring = await Data(await Send(hosts[0], "/api/v1/events",
                Request("Weekly plan", start.AddDays(1), repeat: "weekly", count: 12)));
            var planId = recurring.GetProperty("recurrenceId").GetGuid();
            var publication = await Task.WhenAll(Enumerable.Range(0, 2).Select(async _ =>
                await Data(await Send(hosts[0], $"/api/v1/recurring-events/{planId}/occurrences/1", new { }))));
            var firstPublished = publication[0];
            var repeated = publication[1];
            Check(firstPublished.GetProperty("id").GetGuid() == repeated.GetProperty("id").GetGuid(), "Retry duplicated a recurring event");
            Check(await db.ScalarAsync<long>("SELECT count(*) FROM event WHERE recurrence_id=@planId", new { planId }) == 2,
                "Recurrence generated uncontrolled events");
            Check((await Send(hosts[1], $"/api/v1/recurring-events/{planId}/occurrences/2", new { })).StatusCode == HttpStatusCode.NotFound,
                "Another organizer could publish a plan");
            Check((await Send(hosts[0], $"/api/v1/recurring-events/{planId}/occurrences/11", new { })).StatusCode == HttpStatusCode.Conflict,
                "Early recurring publication allowed");
            Check((await Send(hosts[0], "/api/v1/events", Request("Too many", start.AddDays(4), repeat: "weekly", count: 13))).StatusCode == HttpStatusCode.BadRequest,
                "Unbounded recurrence allowed");
            Check(await db.ScalarAsync<int>("SELECT waitlist_count FROM event WHERE id=@waitingEvent", new { waitingEvent }) == 0,
                "Withdrawn waitlist retained its count");
            var reminderEvent = await Create(hosts[0], Request("Reminder plan", start.AddHours(5), repeat: "weekly", count: 2));
            var reminderPlanId = await db.ScalarAsync<Guid>("SELECT recurrence_id FROM event WHERE id=@reminderEvent", new { reminderEvent });
            using (var pause = new HttpRequestMessage(HttpMethod.Patch, $"/api/v1/recurring-events/{reminderPlanId}") { Content = JsonContent.Create(new { paused = true }) })
            {
                pause.Headers.Add("X-User-Id", hosts[0].ToString());
                await Data(await http.SendAsync(pause));
            }
            Check((await Send(hosts[0], $"/api/v1/recurring-events/{reminderPlanId}/occurrences/1", new { })).StatusCode == HttpStatusCode.Conflict,
                "Paused plan allowed publication");
            using (var resume = new HttpRequestMessage(HttpMethod.Patch, $"/api/v1/recurring-events/{reminderPlanId}") { Content = JsonContent.Create(new { paused = false }) })
            {
                resume.Headers.Add("X-User-Id", hosts[0].ToString());
                await Data(await http.SendAsync(resume));
            }
            var dateLimited = await Data(await Send(hosts[0], "/api/v1/events",
                Request("Date limited", start.AddHours(12), repeat: "weekly") with { RepeatUntil = start.AddDays(15).Date.AddHours(14) }));
            var datePlanId = dateLimited.GetProperty("recurrenceId").GetGuid();
            Check(await db.ScalarAsync<short>("SELECT occurrence_count FROM event_recurrence WHERE id=@datePlanId", new { datePlanId }) == 3,
                "End date did not generate a finite bounded plan");
            var monthlyStart = new DateTime(DateTime.UtcNow.Year+1, 1, 30, 15, 0, 0, DateTimeKind.Utc);
            var monthly = await Data(await Send(hosts[0], "/api/v1/events", Request("Monthly", monthlyStart, repeat: "monthly", count: 3)));
            var plans = await Data(await Get(hosts[0], "/api/v1/me/recurring-events"));
            var monthlySlots = plans.EnumerateArray().Single(plan => plan.GetProperty("id").GetGuid() ==
                monthly.GetProperty("recurrenceId").GetGuid()).GetProperty("occurrences");
            Check(monthlySlots.GetArrayLength() == 3 && monthlySlots[1].GetProperty("startsAt").GetDateTime().AddHours(9).Month == 3,
                "Monthly recurrence did not skip a missing Korean-local calendar date");
            var discovery = await Data(await Get(hosts[0], "/api/v1/activities?q=Weekly%20plan"));
            var discoveryIds = discovery.GetProperty("items").EnumerateArray().Select(item => item.GetProperty("id").GetGuid()).ToArray();
            Check(discoveryIds.Contains(recurring.GetProperty("id").GetGuid()) &&
                !discoveryIds.Contains(firstPublished.GetProperty("id").GetGuid()), "Discovery did not group recurring events");
            var datedDiscovery = await Data(await Get(hosts[0], "/api/v1/activities?q=Weekly%20plan&from=" +
                Uri.EscapeDataString(start.ToString("O"))));
            Check(datedDiscovery.GetProperty("items").EnumerateArray().Any(item =>
                item.GetProperty("id").GetGuid() == firstPublished.GetProperty("id").GetGuid()),
                "Date filter omitted a matching published occurrence");
            var page = await Data(await Get(hosts[0], "/api/v1/me/activities?limit=1&owned=true"));
            Check(page.GetProperty("items").GetArrayLength() == 1 && page.GetProperty("hasMore").GetBoolean(),
                "My activities did not paginate");
            var nextPage = await Data(await Get(hosts[0], "/api/v1/me/activities?limit=1&owned=true&cursor=" +
                Uri.EscapeDataString(page.GetProperty("nextCursor").GetString()!)));
            Check(page.GetProperty("items")[0].GetProperty("id").GetGuid() != nextPage.GetProperty("items")[0].GetProperty("id").GetGuid(),
                "Activity cursor repeated a row");
            var search = await Data(await Get(hosts[0], "/api/v1/me/activities?limit=20&q=Adjacent"));
            Check(search.GetProperty("items").GetArrayLength() == 1, "My activity search ignored query");
            async Task<bool> ShowsEventChat(Guid user) =>
                (await Data(await Get(user, $"/api/v1/events/{c}"))).GetProperty("item").GetProperty("viewer_can_open_chat").GetBoolean();
            Check(await ShowsEventChat(hosts[2]), "Organizer detail hid the activity chat entry");
            Check(await ShowsEventChat(member), "Approved member detail hid the activity chat entry");
            Check(!await ShowsEventChat(second), "Unapproved detail exposed the activity chat entry");
            Check((await Get(member, $"/api/v1/events/{c}/conversation")).IsSuccessStatusCode, "Approved member cannot open event chat");
            Check((await Get(second, $"/api/v1/events/{c}/conversation")).StatusCode == HttpStatusCode.Forbidden,
                "Unapproved user accessed event chat");
            await db.ExecuteAsync("UPDATE conversation_member SET left_at=now() WHERE user_id=@member AND conversation_id IN (SELECT id FROM conversation WHERE event_id=@c)", new { member, c });
            Check((await Get(member, $"/api/v1/events/{c}/conversation")).StatusCode == HttpStatusCode.Forbidden,
                "Chat entry rejoined a voluntarily departed member");
            Check(!await ShowsEventChat(member), "Detail exposed chat after the member left the conversation");
            var reminder = new RecurringEventReminderService(db, app.Services.GetRequiredService<RealtimeConnectionManager>(),
                Microsoft.Extensions.Logging.Abstractions.NullLogger<RecurringEventReminderService>.Instance);
            await reminder.RunOnceAsync(default);
            var reminders = await db.ScalarAsync<long>("SELECT count(*) FROM notification WHERE notification_type='recurrence_due'");
            Check(reminders > 0, "No recurring publication reminder was created");
            await reminder.RunOnceAsync(default);
            Check(reminders == await db.ScalarAsync<long>("SELECT count(*) FROM notification WHERE notification_type='recurrence_due'"),
                "Repeated reminder was not deduplicated");
            await db.ExecuteAsync("UPDATE event SET status='cancelled' WHERE id=@c", new { c });
            await Data(await Send(member, $"/api/v1/events/{a}/join", new { partySize = 1 }));
            Check(await db.ScalarAsync<string>("SELECT status FROM event_member WHERE event_id=@a AND user_id=@member",
                new { a, member }) == "applied", "Withdrawn application could not be submitted after a conflict cleared");
            try
            {
                await db.ExecuteAsync("""
                    UPDATE event_schedule SET starts_at=@startsAt,ends_at=@endsAt
                    WHERE event_id IN (SELECT id FROM event WHERE organizer_user_id=@host AND title='Adjacent')
                    """, new { startsAt = start.AddHours(1), endsAt = start.AddHours(3), host = hosts[0] });
                throw new Exception("Schedule edit introduced an organizer overlap");
            }
            catch (PostgresException error) when (error.ConstraintName == "event_schedule_conflict") { }
            Console.WriteLine("PASS: HTTP creation rollback, adjacent times, overlapping applications, withdrawal notices, concurrent approval, finite/idempotent recurring publication, authorization and reminder deduplication");
        }
        finally { await app.StopAsync(); }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception(message);
    }
}
