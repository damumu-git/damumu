# -*- coding: utf-8 -*-
"""Render the three-language static site. Deploy dist only; no server runtime needed."""
from pathlib import Path
from html import escape

ROOT = Path(__file__).resolve().parent / 'dist'
MAIL = 'damumuapp@gmail.com'
DOMAIN = 'https://www.damumu.com'
DATA = {
'zh': {
'lang':'zh-CN','brand':'搭慕','nav':['首页','隐私政策','使用条款','账号删除','客户支持'],
'hero':['在韩国，把今天变成一起。','一起吃饭、运动、学习、探索城市。从附近的活动开始，认识兴趣相投的人。','寻找下一场相遇'],
'features':['从想去，到一起去','发现附近活动','按城市、地区和兴趣发现活动，定位也可以手动选择。','发起你的计划','设置时间、人数与预计线下花费，让想法变成一次约定。','活动与私聊','获批后进入活动群，也可以通过私聊协调安排。'],
'safe':['好的相遇，也需要边界','集合地点保护','精确集合地点仅向组织者、已获批和已参加的成员开放。申请中、候补和被拒绝者不可见。','举报与社区规则','通过举报处理不当行为。安全见面、紧急联系人和 SOS 不属于 MVP1 已开放功能。'],
'preview':['App 界面示意','周末，一起出门吧','汉江散步','咖啡与交流','轻松去运动','以下为原创界面占位，非真实用户或实时活动。'],
'download':['准备好，遇见同路人。','Android / iOS 即将上线','商店链接尚未发布；下方为不可扫描的二维码占位。','二维码待替换'],
'draft':'上线前待核对：这是按当前代码及运营方信息编写的政策草案。保留期限、境外处理披露和最终删除机制尚需落实；生效日期待确认。',
'privacy_notice':'公告日期：2026年10月20日｜生效日期：2026年10月20日｜版本：1.0。本方针适用于在韩国由个人运营者金成龙运营的搭慕 / 담우 / Damu。',
'privacy':[
['1. 运营者与负责人','搭慕 / 담우 / Damu由居住在韩国的个人运营者金成龙（JIN CHENGLONG）运营，不是公司或法人。个人信息保护负责人：JIN CHENGLONG；隐私、权利申请与投诉邮箱：damumuapp@gmail.com；受理时间：每日06:00–24:00（韩国时间）。'],
['2. 处理项目、目的、依据及期限','本方针附表按服务场景列明必需/选填项目、目的、韩国《个人信息保护法》上的处理依据和保存期限。未列明的新目的或新项目不会直接使用；必要时将另行告知并取得同意。'],
['3. 公开范围与敏感信息','昵称、头像、简介及活动内容按功能所示范围公开；精确集合地点仅组织者及已批准或已参加成员可见。请勿在公开资料或活动内容中填写健康、宗教、政治观点等不必要的敏感信息；可删除选填资料、修改内容或通过邮箱请求限制公开。聊天仅向会话成员展示，但成员可能另行保存副本。'],
['4. 位置与设备权限','附近活动功能经同意后在前台取得可能较精确的经纬度，并用于距离计算及地名转换；不进行后台持续定位。可拒绝定位并手动选择地区。最近位置仅在设备缓存30分钟；相机、照片及通知权限仅在相应功能中请求，可在系统设置撤回。'],
['5. 委托处理与第三方提供','委托情况见附表。除用户选择公开、会话成员之间的必要展示、依法要求或附表所列服务委托外，不向第三方提供个人信息。若将来发生独立的第三方提供，将在提供前另行告知接收方、目的、项目和期限并依法取得同意。'],
['6. 境外转移','主数据库和上传文件位于AWS首尔区域；但推送、Apple设备通知、地名转换及客服邮件可能产生境外处理。接收方、国家、项目、时点/方式、目的、期限、依据和拒绝方法见附表。关闭可选通知或拒绝定位可停止相应的新转移；拒绝后仍可使用站内通知或手动地区选择。'],
['7. 保存、销毁与备份','期限届满或目的完成后及时销毁：数据库记录以不可恢复方式删除，上传文件从存储中删除，纸质资料如有则粉碎。依法必须保存的资料将与一般资料分离并仅在法定范围内使用。生产备份采用最长30日滚动到期；从备份恢复时重新执行删除记录。'],
['8. 用户权利与申请','可请求查阅、传输、更正、删除、停止处理或撤回同意。可在App内修改资料或通过注册邮箱联系；注销路径为“我的→设置→账号管理→删除账号”。本人、法定代理人或受委托代理人均可申请，运营者仅要求必要的身份或代理关系证明，并原则上在10日内答复。拒绝或限制请求时将说明理由及异议方法；异议可回复原处理邮件提出。'],
['9. 自动收集信息','服务运行时自动处理IP地址、访问时间、登录时间、设备平台、FCM安装标识/推送Token及错误日志，用于安全、登录、推送和故障处理。官网不使用广告Cookie或分析追踪器。可在系统设置关闭通知；关闭后不再发送系统推送，但站内通知仍可使用。'],
['10. 安全措施','采取密码加盐哈希、签名登录凭证、最小权限访问控制、精确集合地点授权、参数化数据库访问和删除任务重试等措施。聊天不是端到端加密。运营者持续维护传输保护、备份访问控制、恢复和事故响应措施。'],
['11. 年龄、自动化决定与救济','服务仅面向年满18岁用户，不以未满14岁儿童为对象。当前不作仅依靠自动化处理、并对用户权利产生重大影响的决定。隐私争议也可向韩国个人信息侵害申告中心（118）或个人信息纠纷调解委员会（1833-6972）咨询。'],
['12. 变更与版本','重要变更将通过官网或App公告；新增处理目的、敏感信息处理或依法需要同意的事项会另行取得同意。公告日期与生效日期均为2026年10月20日，版本1.0。后续版本将保留公告日、生效日和历史记录。']
],
'privacy_tables':[
['个人信息处理明细',['场景','项目及必需性','目的/依据','保存期限'],[
['账号及登录','必需：邮箱、密码验证值、昵称、登录时间/IP','注册、认证、安全；合同履行及正当利益','会员期间；注销申请确认后1–2个工作日内清除'],
['个人资料','选填：头像、简介、城市/地区、语言、兴趣、性别、职业、来韩年份、联系方式','资料展示及活动匹配；用户同意','删除、撤回同意或注销时'],
['活动及报名','活动说明、日程、申请内容、成员状态、集合地点、图片','活动发布、报名、成员管理；合同履行','公开内容注销时删除；必要的非识别共享记录至活动结束后1年'],
['聊天','文字、图片、时间、读取/编辑/撤回状态','成员沟通；合同履行','发送后1年；注销时解除资料关联'],
['举报及处罚','双方标识、理由、说明、消息快照、图片证据、处理结果','防滥用及争议处理；正当利益','结案或相关处罚结束后1年'],
['位置','选填：前台设备经纬度、转换后的地区','附近搜索；同意','设备缓存30分钟；服务器不建立长期位置轨迹'],
['推送及日志','选填推送Token；自动生成的安装ID、平台、IP、访问/错误日志','推送、安全和故障处理；同意或正当利益','Token至撤回/失效/注销；普通日志90日，必要安全审计最长1年'],
['客服','邮箱、咨询内容、用户提交的附件','答复咨询及纠纷处理；用户请求/正当利益','结案后1年']]],
['处理委托',['受托方','委托业务','处理资料','地点/期限'],[
['Amazon Web Services Korea LLC','韩国首尔区域基础设施托管','服务数据库及上传文件','韩国；按本方针各项目期限'],
['Google LLC及适用的Google关联公司','Firebase Cloud Messaging及Gmail客服','推送Token、安装ID、平台、通知内容/关联标识；客服邮件','境外处理见下表；提供服务所需期间'],
['Apple Inc.','iOS Apple Push Notification service','设备推送Token、通知内容/关联标识','境外处理见下表；Apple提供服务所需期间'],
['OpenStreetMap Foundation','Nominatim地名转换','用户主动启用定位时的经纬度、请求IP','境外处理见下表；按提供方日志政策']]],
['境外转移',['接收方/国家','项目','时点及方式','目的/期限/依据与拒绝'],[
['Google LLC及关联处理设施／美国及Google设施所在国家','推送Token、安装ID、平台、通知内容/关联标识；客服邮件','启用推送或发送客服邮件时经加密网络传输','推送及客服；服务提供所需期间；《个人信息保护法》第28条之8第1款第1项同意或第3项合同履行必要。可关闭通知或不使用邮件客服'],
['Apple Inc.／美国','iOS推送Token、通知内容/关联标识','向iOS设备发送通知时经加密网络传输','iOS推送；Apple提供服务所需期间；同上。可关闭系统通知'],
['OpenStreetMap Foundation／英国','经纬度、请求IP','用户启用自动定位并转换地名时经加密网络传输','地名转换；按提供方日志政策；同意。可拒绝定位并手动选择地区']]]
],
'terms':[['服务与年龄','搭慕 / 담우 / Damu 由金成龙个人运营，面向年满 18 岁用户提供活动发现、发布、报名及沟通。'],['行为规范','不得诈骗、骚扰、冒充他人、传播违法内容或未经许可披露他人信息。用户对发布内容拥有相应权利，并授予提供服务所必需的展示和传输权限。'],['活动、费用与安全','活动金额为预计线下人均韩元支出，平台不收取活动费，不提供支付、托管、转账或担保。参与者自行确认安排；平台不保证他人的行为或见面安全。MVP1 不提供安全见面或 SOS 服务。紧急危险应直接联系当地紧急机构。'],['限制、退出与申诉','违反规则可能导致内容限制或账号停用。可通过 damumuapp@gmail.com 申诉或申请删除。账号删除与共享内容保留范围见隐私政策。'],['责任与争议','按适用法律处理双方权利与责任，不排除法律不得排除的责任。韩国消费者及个人信息保护规则的适用范围、争议管辖和生效日期仍待法律核对。']],
'deletion':[['在 App 中申请','我的 → 设置 → 账号管理 → 删除账号。填写注册邮箱和当前密码，阅读提示后确认；账号即停用、推送停用并退出登录。'],['无法登录时','从注册邮箱向 damumuapp@gmail.com 发送标题为「Damu 账号删除申请」的邮件。说明注册邮箱及删除意愿即可，不要发送密码、验证码或身份证。运营方验证账号控制权后，在 1–2 个工作日内处理；手机/Google 登录正式接入后需补充对应验证流程。'],['删除与保留范围','清除认证资料、个人资料、头像、推送设备、偏好和本人公开发布内容。共享聊天及图片为成员保留至发送满 1 年，解除发送者资料关联；必要举报/处罚证据结案或相关处罚结束后保留 1 年。已确认：注销时取消未来活动并通知成员；活动公开内容清除，保留无个人资料的必要关联记录。'],['当前实现边界','App/API 已实现密码复核、账号停用、数据库清理、文件重试及定期保留规则；已用隔离合成数据验证，尚未部署。自动清理默认关闭，必须由运营方完成迁移、备份审查和启用验收。停用期间由运营方处理请求，不能仅凭提交成功视为已完成擦除。卸载 App 不等于注销。']],
'support':[['联系我们','邮箱：damumuapp@gmail.com。服务时间：每天 06:00–24:00（韩国时间 UTC+9）。暂无客服电话。账号删除申请处理目标为 1–2 个工作日；一般咨询回复时限待确认。'],['咨询时提供','可提供 App 版本、设备系统、问题发生时间和必要截图。请遮挡第三方个人信息，不要发送密码或验证码。'],['隐私与社区','个人信息负责人：JIN CHENGLONG。隐私访问、更正、注销及举报申诉均可使用同一邮箱。发生即时危险时请直接联系当地紧急机构。']]
},
'en': {
'lang':'en','brand':'Damu','nav':['Home','Privacy policy','Terms','Delete account','Support'],
'hero':['A better day, together.','Find people to eat, move, learn and explore with in Korea. Start with an activity close to you.','Find your next plan'],
'features':['From a plan to a shared day','Explore nearby','Browse activities by city, district and interests. You can select your area manually.','Make a plan','Choose a time, capacity and estimated offline spending.','Keep in touch','Join your activity chat after approval and coordinate through direct messages.'],
'safe':['Good connections need boundaries','Meeting-point privacy','Exact meeting points are available only to organizers and approved or attended members, not pending, waitlisted or rejected applicants.','Community care','Report inappropriate conduct. Safety meetups, emergency contacts and SOS are not available in MVP1.'],
'preview':['App concept preview','Make room for a new plan','A walk by the Han River','Coffee and conversation','Move together','Original interface placeholders, not real users or live activities.'],
'download':['Your next connection starts here.','Android / iOS coming soon','Store links are not available yet. These QR placeholders cannot be scanned.','QR placeholder'],
'draft':'Pre-launch draft: based on current code and operator information. Retention enforcement, overseas processing disclosures and final erasure remain pending. Effective date to be confirmed.',
'privacy_notice':'Announcement: October 20, 2026 | Effective: October 20, 2026 | Version 1.0. This policy applies to Damu / 搭慕 / 담우, operated in Korea by the individual operator JIN CHENGLONG.',
'privacy':[
['1. Operator and privacy lead','Damu / 搭慕 / 담우 is operated in Korea by the individual JIN CHENGLONG, not by a company or other legal entity. Privacy lead: JIN CHENGLONG; privacy, rights and complaint email: damumuapp@gmail.com; reception hours: 06:00–24:00 daily, Korea time.'],
['2. Items, purposes, bases and retention','The tables below identify required and optional data, purpose, basis under Korea’s Personal Information Protection Act, and retention for each service activity. New items or purposes will not be used without prior notice and consent where required.'],
['3. Visibility and sensitive data','Nickname, avatar, biography and activity content appear to the audience shown in the feature. Exact meeting points are limited to organizers and approved or attended members. Do not put unnecessary health, religion, political opinion or other sensitive data in public fields. Optional profile data can be removed, and visibility restrictions can be requested by email. Chats are visible to conversation members, who may keep separate copies.'],
['4. Location and device permissions','With permission, nearby search obtains potentially precise foreground coordinates for distance and place-name lookup; there is no continuous background tracking. You can refuse and select a region manually. The latest location is cached on the device for 30 minutes. Camera, photo and notification permissions are requested only for the related feature and can be withdrawn in system settings.'],
['5. Processors and third-party disclosure','Processors are listed below. Other than user-directed publication, necessary display to conversation members, legal requirements and the listed processors, personal data is not disclosed to third parties. Any future independent disclosure will identify the recipient, purpose, items and retention and obtain consent where required.'],
['6. Overseas transfers','The main database and uploads are in the AWS Seoul region. Push delivery, Apple device notifications, place-name lookup and support email may involve processing outside Korea. Recipients, countries, items, timing/method, purpose, retention, basis and refusal options are listed below. Refusing location or optional push stops the related new transfer; manual regions and in-app notifications remain available.'],
['7. Retention, erasure and backups','When a period expires or a purpose ends, database records are irreversibly deleted, uploaded files are removed and any paper records are shredded. Records required by law are separated and used only for that legal purpose. Production backups expire on a rolling basis within 30 days; deletion records are replayed after restoration.'],
['8. Your rights and requests','You may request access, transmission, correction, deletion, restriction or withdrawal of consent. Edit profile data in the App or email from the registered address. Deletion: My → Settings → Account management → Delete account. The user, legal representative or authorized agent may request; only necessary identity/authority evidence is required. The operator normally responds within 10 days. A refusal or restriction will state reasons and objection steps; reply to that notice to object.'],
['9. Automatically collected data','The service automatically processes IP address, access/login time, device platform, FCM installation ID/push token and error logs for security, sign-in, push and troubleshooting. The website uses no advertising cookies or analytics trackers. System push can be disabled in device settings while in-app notifications remain available.'],
['10. Safeguards','Measures include salted password hashing, signed credentials, least-privilege access checks, exact-meeting-point authorization, parameterized database access and retryable deletion jobs. Chats are not end-to-end encrypted. The operator maintains transport protection, backup access controls, recovery and incident-response measures.'],
['11. Age, automated decisions and remedies','The service is for adults aged 18 and over and is not directed to children under 14. It does not currently make decisions based solely on automated processing that significantly affect user rights. Privacy complaints may also be directed to Korea’s Privacy Infringement Report Center (118) or Personal Information Dispute Mediation Committee (1833-6972).'],
['12. Changes and version','Material changes will be announced in the App or website. New purposes, sensitive-data processing or other consent-based changes will obtain separate consent where required. Announced and effective October 20, 2026; version 1.0. Future versions will retain announcement, effective-date and history information.']
],
'privacy_tables':[
['Processing details',['Activity','Items / requirement','Purpose / basis','Retention'],[
['Account and sign-in','Required: email, password verifier, nickname, login time/IP','Registration, authentication and security; contract and legitimate interests','Membership; erase within 1–2 business days after verified deletion request'],
['Profile','Optional: avatar, biography, city/district, language, interests, gender, occupation, arrival year, contact details','Profile display and activity matching; consent','Until deletion, consent withdrawal or account deletion'],
['Activities/applications','Activity details, schedule, application, member status, meeting point, images','Publishing, applications and membership; contract','Public content removed at deletion; necessary de-identified shared records up to one year after activity'],
['Chat','Text, images, timestamps, read/edit/recall status','Member communication; contract','One year from sending; unlink profile on account deletion'],
['Reports/penalties','Party IDs, reason, description, message snapshot, image evidence, outcome','Abuse prevention and disputes; legitimate interests','One year after case closure or related sanction ends'],
['Location','Optional foreground coordinates and derived region','Nearby search; consent','30-minute device cache; no long-term server location trail'],
['Push/logs','Optional push token; installation ID, platform, IP, access/error logs','Push, security, troubleshooting; consent or legitimate interests','Token until withdrawal/invalid/deletion; ordinary logs 90 days, necessary security audit up to one year'],
['Support','Email, inquiry and submitted attachments','Answer and dispute handling; request/legitimate interests','One year after closure']]],
['Processors',['Processor','Service','Data','Location / term'],[
['Amazon Web Services Korea LLC','Infrastructure in the Seoul region','Service database and uploaded files','Korea; each item’s period above'],
['Google LLC and applicable Google affiliates','Firebase Cloud Messaging and Gmail support','Push token, installation ID, platform, notification content/related IDs; support email','See transfers below; while needed to provide service'],
['Apple Inc.','Apple Push Notification service for iOS','Device push token, notification content/related IDs','See transfers below; while Apple provides the service'],
['OpenStreetMap Foundation','Nominatim place-name lookup','Coordinates and request IP when automatic location is enabled','See transfers below; provider log period']]],
['Overseas transfers',['Recipient / country','Items','Timing and method','Purpose / term / basis and refusal'],[
['Google LLC and affiliated facilities / United States and countries where Google maintains facilities','Push token, installation ID, platform, notification content/related IDs; support email','Encrypted network transfer when push is enabled or support email sent','Push/support; service term; PIPA Art. 28-8(1)(1) consent or (3) contract necessity. Disable push or do not use email support'],
['Apple Inc. / United States','iOS push token, notification content/related IDs','Encrypted transfer when an iOS notification is sent','iOS push; Apple service term; same basis. Disable system notifications'],
['OpenStreetMap Foundation / United Kingdom','Coordinates and request IP','Encrypted transfer when automatic location performs place-name lookup','Place-name lookup; provider log period; consent. Refuse location and choose region manually']]]
],
'terms':[['Service and age','Damu / 搭慕 / 담우 is operated by 金成龙 for users aged 18 and over, offering activity discovery, creation, applications and communication.'],['Conduct and content','Do not commit fraud, harass, impersonate, publish unlawful content or disclose others’ information without permission. You must hold the rights to posted content and grant only the display and transmission rights needed to provide the service.'],['Activities, costs and safety','Amounts are estimated offline per-person KRW spending. The platform does not collect activity fees or provide payments, escrow, transfers or guarantees. Verify arrangements yourself. The platform cannot guarantee others’ conduct or offline safety. MVP1 does not provide safety meetups or SOS. Contact local emergency services for immediate danger.'],['Restrictions and appeals','Rule violations may lead to content restrictions or account suspension. Appeal or request deletion at damumuapp@gmail.com. See the privacy policy for shared-content retention.'],['Liability and disputes','Applicable law governs rights and liabilities; non-excludable legal liability is not waived. Korean consumer/privacy requirements, jurisdiction and effective date require legal review.']],
'deletion':[['Request in the App','My → Settings → Account management → Delete account. Enter your registered email and current password and confirm. The account and push notifications are disabled, and you are signed out.'],['If you cannot sign in','Email damumuapp@gmail.com from your registered mailbox with subject “Damu account deletion request”. Provide the registered address and request, never passwords, codes or ID documents. After verifying control, the operator targets processing in 1–2 business days. Future phone/Google sign-in needs its corresponding verification flow.'],['Removal and retention','Removal covers credentials, profile, avatar, push devices, preferences and public posts. Shared messages/images remain for one year from sending without profile linkage; necessary report/penalty evidence remains for one year after closure or the end of a related sanction. Confirmed: cancel upcoming activities and notify members; remove public activity content while retaining only necessary unlinked shared records.'],['Implementation status','Password verification, suspension, database erasure, retryable file removal and scheduled retention are implemented and tested with isolated synthetic data, not deployed. Automatic cleanup is disabled by default pending migration, backup review and deployment acceptance. The operator must handle requests while it is disabled. Acceptance of a request does not mean erasure has finished. Uninstallation is not deletion.']],
'support':[['Contact','Email: damumuapp@gmail.com. Daily 06:00–24:00, Korea time (UTC+9). No telephone support. Deletion requests target 1–2 business days; the general response target is not yet set.'],['Useful details','Include App version, operating system, issue time and necessary screenshots. Redact other people’s personal information. Never send passwords or verification codes.'],['Privacy and community','Privacy contact: JIN CHENGLONG. Use the same mailbox for access, correction, deletion and report appeals. For immediate danger, contact local emergency services.']]
},
'ko': {
'lang':'ko','brand':'담우','nav':['홈','개인정보 처리방침','이용약관','계정 삭제','고객지원'],
'hero':['한국 생활, 함께하는 오늘.','같이 먹고, 운동하고, 배우고, 도시를 탐험해요. 가까운 모임에서 취향이 맞는 사람을 만나보세요.','다음 모임 찾아보기'],
'features':['생각에서 함께하는 하루로','주변 모임 발견','도시·지역·관심사로 모임을 살펴보세요. 지역은 직접 선택할 수도 있어요.','나의 계획 만들기','시간, 인원, 예상 오프라인 비용을 정해 모임을 열어요.','모임과 개인 대화','승인 후 모임 채팅에 참여하고 개인 메시지로 일정을 조율해요.'],
'safe':['좋은 만남에는 경계가 필요해요','정확한 장소 보호','정확한 집합 장소는 주최자와 승인·참석 회원만 볼 수 있습니다. 신청·대기·거절 상태에는 공개하지 않습니다.','신고와 커뮤니티','부적절한 행동을 신고할 수 있습니다. 안전 만남, 긴급 연락처, SOS는 MVP1 제공 기능이 아닙니다.'],
'preview':['앱 화면 예시','주말, 같이 나가요','한강 산책','카페에서 대화','함께 운동해요','직접 제작한 화면 예시이며 실제 사용자나 실시간 모임이 아닙니다.'],
'download':['함께할 사람을 만나보세요.','Android / iOS 출시 준비 중','스토어 링크는 아직 없습니다. QR 영역은 스캔할 수 없는 자리표시자입니다.','QR 준비 중'],
'draft':'출시 전 검토 초안: 현재 코드와 운영자 정보를 반영했습니다. 보유기간 집행, 국외 처리 고지 및 최종 파기는 미완료이며 시행일은 확정 전입니다.',
'privacy_notice':'공고일자: 2026년 10월 20일 | 시행일자: 2026년 10월 20일 | 버전 1.0. 이 방침은 대한민국에서 개인 운영자 JIN CHENGLONG이 운영하는 담우 / 搭慕 / Damu에 적용됩니다.',
'privacy':[
['1. 운영자 및 보호책임자','담우 / 搭慕 / Damu는 대한민국에서 개인 JIN CHENGLONG(김성룡)이 운영하며 회사나 법인이 아닙니다. 개인정보 보호책임자: JIN CHENGLONG. 개인정보 문의·권리행사·민원 이메일: damumuapp@gmail.com. 접수시간: 매일 06:00–24:00(한국시간).'],
['2. 처리 항목·목적·근거·기간','아래 표에 서비스별 필수/선택 항목, 목적, 개인정보 보호법상 근거와 보유기간을 공개합니다. 고지하지 않은 새로운 목적이나 항목은 바로 사용하지 않으며 필요한 경우 별도 고지와 동의를 진행합니다.'],
['3. 공개 범위와 민감정보','닉네임·사진·소개와 모임 내용은 기능에 표시된 범위에서 공개됩니다. 정확한 집합 장소는 주최자와 승인·참석 회원만 볼 수 있습니다. 공개 입력란에 건강, 종교, 정치적 견해 등 불필요한 민감정보를 입력하지 마세요. 선택 프로필을 삭제하거나 내용을 수정할 수 있고 이메일로 공개 제한을 요청할 수 있습니다. 채팅은 대화 참여자에게만 보이나 참여자가 별도 사본을 보관할 수 있습니다.'],
['4. 위치와 기기 권한','동의한 경우 주변 모임 기능에서 전경의 비교적 정확한 좌표를 받아 거리 계산과 지명 변환에 사용하며 백그라운드에서 계속 추적하지 않습니다. 위치를 거부하고 지역을 직접 선택할 수 있습니다. 최근 위치는 기기에 30분간 캐시됩니다. 카메라·사진·알림 권한은 관련 기능에서만 요청하며 시스템 설정에서 철회할 수 있습니다.'],
['5. 처리위탁과 제3자 제공','처리위탁 현황은 아래 표와 같습니다. 이용자가 선택한 공개, 대화 참여자에게 필요한 표시, 법령상 요구 및 표에 적은 위탁 외에는 개인정보를 제3자에게 제공하지 않습니다. 향후 독립적인 제3자 제공이 발생하면 제공받는 자, 목적, 항목과 기간을 먼저 알리고 필요한 동의를 받습니다.'],
['6. 국외 이전','주 데이터베이스와 업로드 파일은 AWS 서울 리전에 있습니다. 다만 푸시, Apple 기기 알림, 지명 변환, 고객문의 메일은 국외에서 처리될 수 있습니다. 이전받는 자, 국가, 항목, 시점·방법, 목적, 기간, 근거와 거부방법은 아래 표와 같습니다. 선택 알림 또는 위치를 거부하면 관련 신규 이전을 중단하며 앱 내 알림이나 직접 지역 선택은 계속 이용할 수 있습니다.'],
['7. 보유·파기 및 백업','보유기간이 끝나거나 목적이 달성되면 DB 기록을 복구할 수 없도록 삭제하고 업로드 파일을 제거하며 종이 자료가 있으면 파쇄합니다. 법령에 따라 보존하는 자료는 일반 자료와 분리하고 법정 목적에만 사용합니다. 운영 백업은 최장 30일 순환 만료하며 백업 복원 시 삭제 기록을 다시 적용합니다.'],
['8. 정보주체 권리와 신청','열람·전송·정정·삭제·처리정지·동의철회를 요구할 수 있습니다. 앱에서 프로필을 수정하거나 가입 이메일로 신청하세요. 탈퇴 경로: 내 정보→설정→계정 관리→계정 삭제. 본인, 법정대리인 또는 위임받은 대리인이 신청할 수 있고 필요한 최소한의 본인·대리관계 확인만 합니다. 원칙적으로 10일 안에 답변하며 거절·제한 시 이유와 이의방법을 알립니다. 이의는 결과 메일에 회신하여 제기할 수 있습니다.'],
['9. 자동 수집 정보','서비스 운영 중 IP주소, 접근·로그인 시각, 기기 플랫폼, FCM 설치 ID·푸시토큰 및 오류 로그를 자동 처리하여 보안·로그인·푸시·장애 대응에 사용합니다. 홈페이지는 광고 쿠키나 분석 추적기를 사용하지 않습니다. 시스템 설정에서 푸시를 끌 수 있으며 앱 내 알림은 계속 이용할 수 있습니다.'],
['10. 안전성 확보조치','솔트를 사용한 비밀번호 해시, 서명된 로그인 정보, 최소권한 접근검사, 정확한 장소 권한, 매개변수화 DB 접근, 삭제 작업 재시도를 적용합니다. 채팅은 종단간 암호화가 아닙니다. 운영자는 전송 보호, 백업 접근통제, 복구 및 사고 대응조치를 유지합니다.'],
['11. 연령·자동화 결정·구제','서비스는 만 18세 이상을 대상으로 하며 만 14세 미만 아동을 대상으로 하지 않습니다. 현재 완전히 자동화된 처리만으로 이용자 권리에 중대한 영향을 주는 결정을 하지 않습니다. 개인정보침해 신고센터(118) 또는 개인정보분쟁조정위원회(1833-6972)에도 상담할 수 있습니다.'],
['12. 변경과 버전','중요 변경은 앱 또는 홈페이지에 공지합니다. 새로운 목적, 민감정보 처리 등 동의가 필요한 변경은 별도 동의를 받습니다. 공고일과 시행일은 2026년 10월 20일이며 버전은 1.0입니다. 이후 버전은 공고일·시행일과 변경 이력을 보관합니다.']
],
'privacy_tables':[
['개인정보 처리 내역',['구분','항목·필수 여부','목적·근거','보유기간'],[
['계정·로그인','필수: 이메일, 비밀번호 검증값, 닉네임, 로그인 시각/IP','가입·인증·보안; 계약 이행 및 정당한 이익','회원기간; 확인된 탈퇴 신청 후 1~2영업일 내 파기'],
['프로필','선택: 사진, 소개, 도시/지역, 언어, 관심사, 성별, 직업, 입국연도, 연락처','프로필 표시·모임 연결; 동의','삭제·동의철회·탈퇴 시까지'],
['모임·신청','모임 설명, 일정, 신청 내용, 회원 상태, 집합 장소, 이미지','모임 게시·신청·회원관리; 계약 이행','탈퇴 시 공개 내용 삭제; 필요한 비식별 공유 기록은 모임 종료 후 1년'],
['채팅','문자, 이미지, 시각, 읽음·수정·취소 상태','회원 소통; 계약 이행','발송 후 1년; 탈퇴 시 프로필 연결 해제'],
['신고·제재','당사자 ID, 사유, 설명, 메시지 스냅샷, 이미지 증거, 결과','부정이용 방지·분쟁 대응; 정당한 이익','종결 또는 관련 제재 종료 후 1년'],
['위치','선택: 전경 좌표, 변환된 지역','주변 검색; 동의','기기 캐시 30분; 서버에 장기 위치이력 미구축'],
['푸시·로그','선택 푸시토큰; 설치ID, 플랫폼, IP, 접근·오류 로그','푸시·보안·장애 대응; 동의 또는 정당한 이익','토큰은 철회·무효·탈퇴 시까지; 일반 로그 90일, 필요한 보안감사 최대1년'],
['고객문의','이메일, 문의 내용, 제출 첨부','답변·분쟁 처리; 이용자 요청/정당한 이익','종결 후 1년']]],
['개인정보 처리위탁',['수탁자','위탁 업무','처리 정보','장소·기간'],[
['Amazon Web Services Korea LLC','서울 리전 인프라 호스팅','서비스 DB와 업로드 파일','대한민국; 각 항목 보유기간'],
['Google LLC 및 적용되는 Google 관계사','Firebase Cloud Messaging, Gmail 고객문의','푸시토큰, 설치ID, 플랫폼, 알림 내용/관련 ID; 문의메일','아래 국외이전 표 참조; 서비스 제공에 필요한 기간'],
['Apple Inc.','iOS Apple Push Notification service','기기 푸시토큰, 알림 내용/관련 ID','아래 국외이전 표 참조; Apple 서비스 제공기간'],
['OpenStreetMap Foundation','Nominatim 지명 변환','자동 위치 사용 시 좌표와 요청 IP','아래 국외이전 표 참조; 제공자 로그 정책 기간']]],
['개인정보 국외 이전',['이전받는 자·국가','항목','시점·방법','목적·기간·근거 및 거부'],[
['Google LLC 및 관계 처리시설 / 미국 및 Google 시설 소재 국가','푸시토큰, 설치ID, 플랫폼, 알림 내용/관련 ID; 문의메일','푸시 활성화 또는 문의메일 발송 시 암호화 통신','푸시·문의; 서비스 제공기간; 보호법 제28조의8 제1항 제1호 동의 또는 제3호 계약 이행 필요. 알림 해제 또는 이메일 문의 미사용 가능'],
['Apple Inc. / 미국','iOS 푸시토큰, 알림 내용/관련 ID','iOS 알림 발송 시 암호화 통신','iOS 푸시; Apple 서비스 제공기간; 같은 근거. 시스템 알림 해제 가능'],
['OpenStreetMap Foundation / 영국','좌표, 요청 IP','자동 위치의 지명 변환 시 암호화 통신','지명 변환; 제공자 로그 정책 기간; 동의. 위치를 거부하고 지역 직접 선택 가능']]]
],
'terms':[['서비스와 연령','담우 / 搭慕 / Damu는 개인 운영자 金成龙이 만 18세 이상 이용자에게 모임 탐색·게시·신청·대화를 제공합니다.'],['이용 규칙과 콘텐츠','사기·괴롭힘·사칭·불법 게시·무단 개인정보 공개를 금지합니다. 이용자는 콘텐츠 권리를 보유해야 하며 서비스 제공에 필요한 표시·전송 권한을 허용합니다.'],['모임·비용·안전','표시 금액은 오프라인 예상 1인당 원화 지출입니다. 플랫폼은 모임비 수납·결제·송금·에스크로·보증을 제공하지 않습니다. 약속을 직접 확인해야 하며 타인의 행동이나 오프라인 안전을 보장하지 않습니다. MVP1은 안전 만남·SOS를 제공하지 않습니다. 즉각적인 위험은 현지 긴급기관에 연락하세요.'],['제한과 이의 제기','위반 시 콘텐츠 제한이나 계정 정지가 가능합니다. 이의 또는 삭제 요청은 damumuapp@gmail.com으로 보내세요. 공유 콘텐츠 보관은 개인정보 처리방침을 확인하세요.'],['책임과 분쟁','적용 법률에 따라 권리·책임을 정하며 법적으로 배제할 수 없는 책임을 면제하지 않습니다. 한국 소비자·개인정보 규정, 관할 및 시행일은 법률 검토가 필요합니다.']],
'deletion':[['앱에서 신청','내 정보 → 설정 → 계정 관리 → 계정 삭제. 가입 이메일과 현재 비밀번호를 입력하고 확인합니다. 계정과 푸시가 비활성화되며 로그아웃됩니다.'],['로그인할 수 없는 경우','가입 이메일에서 damumuapp@gmail.com으로 제목 「Damu 계정 삭제 요청」을 보내세요. 가입 이메일과 삭제 의사를 적고 비밀번호·인증번호·신분증은 보내지 마세요. 계정 소유 확인 후 1~2영업일 내 처리를 목표로 합니다. 휴대전화/Google 로그인 출시 시 별도 인증 절차가 필요합니다.'],['삭제와 보관 범위','인증정보·프로필·사진·푸시 기기·설정·본인 공개 게시물을 삭제합니다. 공동 채팅·사진은 발송일부터 1년간 다른 참여자를 위해 보관하고 프로필 연결을 해제합니다. 필요한 신고·제재 증거는 종결 또는 관련 제재 종료 후 1년간 보관합니다. 예정된 주최 모임을 취소하고 회원에게 알리며 공개 콘텐츠는 삭제하고 필요한 공유 기록만 유지하기로 확정했습니다.'],['현재 구현 범위','비밀번호 확인, 계정 비활성화, DB 파기, 파일 삭제 재시도, 정기 보유기간 처리를 구현하고 격리된 합성 데이터로 검증했으나 아직 배포하지 않았습니다. 자동 정리는 기본 비활성화이며 마이그레이션·백업 검토·배포 검증 후 운영자가 켜야 합니다. 비활성 상태에서는 운영자가 신청을 처리해야 하며 접수만으로 파기 완료를 의미하지 않습니다. 앱 제거는 탈퇴가 아닙니다.']],
'support':[['문의','damumuapp@gmail.com. 매일 06:00~24:00, 한국시간 UTC+9. 전화 상담은 없습니다. 삭제 요청은 1~2영업일 처리가 목표이며 일반 문의 답변 기한은 미확정입니다.'],['문의에 필요한 정보','앱 버전, 운영체제, 발생 시각과 필요한 화면을 알려주세요. 타인의 개인정보는 가리고 비밀번호·인증번호는 보내지 마세요.'],['개인정보와 커뮤니티','개인정보 보호책임자: JIN CHENGLONG. 열람·정정·탈퇴·신고 이의 제기는 같은 이메일로 가능합니다. 즉각적인 위험은 현지 긴급기관에 연락하세요.']]
}}

PAGES=['index','privacy','terms','account-deletion','support']
def filename(page,lang): return page+('' if lang=='zh' else '-'+lang)+'.html'
def esc(v): return escape(v,quote=True)
def render_table(spec):
    title, headers, rows = spec
    head = ''.join(f'<th scope="col">{esc(value)}</th>' for value in headers)
    body = ''.join('<tr>'+''.join(f'<td>{esc(value)}</td>' for value in row)+'</tr>' for row in rows)
    return f'<section><h2>{esc(title)}</h2><table><thead><tr>{head}</tr></thead><tbody>{body}</tbody></table></section>'
def render(lang,page):
    d=DATA[lang]; title=d['nav'][PAGES.index(page)]; nav=''.join('<a href="'+filename(p,lang)+'">'+esc(n)+'</a>' for p,n in zip(PAGES,d['nav']))
    switch=''.join('<a hreflang="'+DATA[l]['lang']+'" href="'+filename(page,l)+'"'+(' aria-current="page"' if l==lang else '')+'>'+n+'</a>' for l,n in [('zh','中文'),('en','English'),('ko','한국어')])
    head=f'''<!doctype html><html lang="{d['lang']}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{esc(title)} | {esc(d['brand'])} · Damu</title><meta name="description" content="{esc(d['hero'][1])}"><link rel="canonical" href="{DOMAIN}/{filename(page,lang)}"><link rel="stylesheet" href="styles.css"><link rel="stylesheet" href="languages.css"><link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='18' fill='%23ff6b5f'/%3E%3Ctext x='16' y='46' fill='white' font-size='44'%3ED%3C/text%3E%3C/svg%3E">'''
    head+=''.join(f'<link rel="alternate" hreflang="{DATA[l]["lang"]}" href="{DOMAIN}/{filename(page,l)}">' for l in DATA)
    head+=f'''</head><body><header class="nav"><div class="wrap navin"><a class="brand" href="{filename('index',lang)}"><span class="brandmark">D</span>{esc(d['brand'])}</a><nav class="links" aria-label="Navigation">{nav}</nav><button class="menu" aria-label="Menu" aria-expanded="false">☰</button></div><nav class="wrap langnav" aria-label="Language">{switch}</nav></header>'''
    if page=='index':
        h=d['hero']; f=d['features']; s=d['safe']; p=d['preview']; a=d['download']
        cards=''.join(f'<article class="feature"><div class="icon">{icon}</div><h3>{esc(f[i])}</h3><p>{esc(f[i+1])}</p></article>' for i,icon in [(1,'⌖'),(3,'♡'),(5,'✦')])
        phone=f'<div class="phone"><div class="screen"><div class="screen-title">{esc(p[1])}</div>'+''.join(f'<div class="event"><div class="event-art">{icon}</div><div><b>{esc(p[i])}</b><p>Seoul · Damu</p></div></div>' for i,icon in [(2,'☀'),(3,'☕'),(4,'◎')])+'</div></div>'
        content=f'''<main><section class="hero"><div class="wrap hero-grid"><div><span class="eyebrow">搭慕 · 담우 · Damu</span><h1>{esc(h[0])}</h1><p class="lead">{esc(h[1])}</p><a class="btn dark" href="#features">{esc(h[2])}</a><p class="micro">{esc(a[1])}</p></div><div class="phone-stage"><div class="orb one"></div><div class="orb two"></div>{phone}</div></div></section><section id="features" class="section white"><div class="wrap"><h2>{esc(f[0])}</h2><div class="feature-grid">{cards}</div></div></section><section class="section"><div class="wrap safe-grid"><div class="safe-panel"><span class="shield">♡</span><h2>{esc(s[0])}</h2></div><div class="safety-list"><article class="safety-item"><span>⌖</span><div><h3>{esc(s[1])}</h3><p>{esc(s[2])}</p></div></article><article class="safety-item"><span>✓</span><div><h3>{esc(s[3])}</h3><p>{esc(s[4])}</p></div></article></div></div></section><section class="section white"><div class="wrap"><h2>{esc(p[0])}</h2><p>{esc(p[5])}</p><div class="preview-row">'''
        content+=''.join(f'<div class="mini-phone"><div class="mock-title">{esc(p[1])}</div><div class="profile-card"><span class="big-avatar">{icon}</span></div><h3>{esc(p[i])}</h3><p>{esc(p[5])}</p></div>' for i,icon in [(2,'☀'),(3,'☕'),(4,'◎')])
        content+=f'''</div></div></section><section class="download"><div class="wrap download-box"><div><h2>{esc(a[0])}</h2><p>{esc(a[1])}</p><p>{esc(a[2])}</p><div class="store-row"><button class="store" disabled>Google Play</button><button class="store" disabled>App Store</button></div></div><div class="qr-row">'''+''.join(f'<div class="qr-card"><div class="qr-empty">QR</div><b>{store}</b><p>{esc(a[3])}</p></div>' for store in ['Google Play','App Store'])+'</div></div></section></main>'
    else:
        key='deletion' if page=='account-deletion' else page
        notice=d['privacy_notice'] if page=='privacy' else d['draft']
        content=f'<main><section class="legal-hero"><div class="wrap"><h1>{esc(title)}</h1><p>搭慕 · 담우 · Damu</p></div></section><section class="legal"><article><div class="notice">{esc(notice)}</div>'
        content+=''.join(f'<section><h2>{esc(t)}</h2><p>{esc(v)}</p></section>' for t,v in d[key])
        if page=='privacy':
            content+=''.join(render_table(spec) for spec in d['privacy_tables'])
        content+=f'<p><a class="btn dark" href="mailto:{MAIL}">{MAIL}</a></p>'
        if page=='privacy':
            content+='<p><a href="https://firebase.google.com/support/privacy">Firebase privacy</a> · <a href="https://osmfoundation.org/wiki/Privacy_Policy">OSMF privacy</a> · <a href="https://www.apple.com/legal/privacy/">Apple privacy</a></p>'
        content+='</article></section></main>'
    return head+content+f'<footer class="footer"><div class="wrap"><a class="brand" href="{filename("index",lang)}">搭慕 · 담우 · Damu</a><div class="footlinks">{nav}</div><p><a href="mailto:{MAIL}">{MAIL}</a></p><div class="copyright">© <span data-year>2026</span> Damu · www.damumu.com</div></div></footer><script src="script.js"></script></body></html>\n'

if __name__=='__main__':
    for lang in DATA:
        for page in PAGES:
            ROOT.joinpath(filename(page,lang)).write_text(render(lang,page),encoding='utf-8')
    print('Rendered 15 static pages; Chinese default.')
