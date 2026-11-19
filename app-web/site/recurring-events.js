export function createRecurringPage({ show, node, button, actionLink, request, showError, time, refreshCurrentPage }) {
  async function render(previous) {
    if (previous) return refreshCurrentPage(previous, () => renderContent(true));
    return renderContent(false);
  }
  async function renderContent(deferred) {
    const content = show("定期活动计划", "workspace-page", false, deferred);
    content.append(node("p", "每场独立报名。确认发布后才会出现在活动列表，暂停计划会停止后续场次提醒。", "meta"));
    try {
      const plans = await request("/me/recurring-events", { auth: true });
      if (!plans.length) content.append(node("p", "暂无定期活动计划。可在发布活动时选择每周或每月。", "meta"));
      for (const plan of plans) {
        const section = node("section", null, "activity-section recurring-plan");
        section.append(node("h2", plan.title), node("p",
          (plan.frequency === "weekly" ? "每周" : "每月") + " · " + (plan.completed ? "已完成" : plan.paused ? "已暂停" : "进行中"), "meta"));
        const pause = button(plan.paused ? "恢复计划" : "暂停计划", async () => {
          pause.disabled = true;
          try {
            await request("/recurring-events/" + plan.id, {
              auth: true, method: "PATCH", data: { paused: !plan.paused },
            });
            await render(content);
          } catch (error) {
            showError(section, error);
            pause.disabled = false;
          }
        });
        if (!plan.completed) section.append(pause);
        const list = node("ul", null, "recurring-occurrences");
        for (const slot of plan.occurrences) {
          const row = node("li");
          row.append(node("span", time(slot.startsAt) + " — " + time(slot.endsAt)));
          if (slot.eventId) {
            row.append(actionLink(slot.status === "cancelled" ? "已取消 · 查看活动" : "查看已发布活动",
              "/activities/" + slot.eventId));
          } else if (slot.canPublish) {
            const publish = button("确认发布本场", async () => {
              publish.disabled = true;
              try {
                const result = await request("/recurring-events/" + plan.id + "/occurrences/" + slot.index,
                  { auth: true, data: {} });
                location.assign("/activities/" + result.id);
              } catch (error) {
                showError(section, error);
                publish.disabled = false;
              }
            }, "button primary");
            row.append(publish);
          } else {
            row.append(node("span", Date.parse(slot.startsAt) <= Date.now() ? "已过期" :
              plan.paused ? "计划已暂停" : "开始前14天可发布", "meta"));
          }
          list.append(row);
        }
        section.append(list);
        content.append(section);
      }
    } catch (error) { showError(content, error); }
    return content;
  }
  return render;
}
