const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {JSDOM,VirtualConsole}=require(process.argv[2] || 'jsdom');
const dir=path.join(__dirname,'dist/assets');
const code=fs.readFileSync(path.join(dir,fs.readdirSync(dir).find(n=>n.endsWith('.js'))),'utf8');
const css=fs.readFileSync(path.join(dir,fs.readdirSync(dir).find(n=>n.endsWith('.css'))),'utf8');
assert(css.includes('--primary:#1769c2'));assert(css.includes('--on-primary:'));
const date='2026-10-27T12:00:00Z';
const user={id:'ui-user',nickname:'UI User',role:'organizer',status:'active',trust_score:4.8,created_at:date,last_login_at:date,attended_count:3,no_show_count:0,report_count:0};
const item={id:'ui-event',title:'UI Event',organizer_name:'UI User',status:'published',starts_at:date,created_at:date,approved_count:2,capacity:6,report_count:0,waitlist_count:0};
const fixture={
'/admin/dashboard':{metrics:{total_users:1,active_events:1},trend:[{day:date,users:1,applications:1}],recentEvents:[item],priorityReports:[]},
'/admin/users':[user],'/admin/users/ui-user':{user,events:[{...item,event_status:'published'}],reports:[],positiveTags:[]},
'/admin/events':[item],'/admin/events/ui-event':{item,schedules:[{id:'schedule',starts_at:date,ends_at:date,status:'scheduled',timezone:'Asia/Seoul'}],members:[{user_id:'ui-user',nickname:'UI User',status:'applied',member_role:'member',trust_score:4.8,created_at:date}],reports:[],actions:[]},
'/emoji-assets':[{key:'coffee',emoji:'☕',name:'咖啡',image_url:'https://media.invalid/coffee.png',byte_size:4000,is_active:true}], '/admin/emoji-assets':[{key:'coffee',emoji:'☕',name:'咖啡',image_url:'https://media.invalid/coffee.png',byte_size:4000,is_active:true}], '/admin/reports':[], '/admin/safety-alerts':[],
'/admin/categories':[{id:'ui-category',code:'outdoor',name_zh_cn:'UI Category',name_en_us:'Outdoors',name_ko_kr:'야외',full_path:'UI Category',level:1,is_active:true,icon:'🌿',color:'#52809d'}],
'/admin/regions':[{code:'KR-11',level:1,name_zh_cn:'UI Region',name_en_us:'Seoul',name_ko_kr:'서울',is_active:true}],
'/admin/system-avatars':[{id:'ui-avatar',code:'ui_avatar',name_zh_cn:'UI Avatar',is_active:true,image_url:'',byte_size:123}],
'/admin/audit':[], '/admin/feature-flags':[{key:'ui_flag',enabled:false,updated_at:date,version:1}],
};
const calls=[],mutations=[],errors=[];const vc=new VirtualConsole();vc.on('jsdomError',e=>errors.push(e.message));
const dom=new JSDOM('<div id="root"></div>',{url:'https://preview.invalid/',runScripts:'outside-only',virtualConsole:vc});
const w=dom.window;
w.HTMLDialogElement.prototype.showModal=function(){this.open=true;};
w.HTMLDialogElement.prototype.close=function(){this.open=false;};
w.prompt=()=>{throw Error('Native prompt is forbidden');};
w.confirm=()=>{throw Error('Native confirm is forbidden');};
w.fetch=async(url,options={})=>{const raw=new URL(url,w.location.href).pathname;const endpoint=raw.replace(/^\/api\/v1/,'');calls.push(endpoint);if(options.method && options.method!=="GET")mutations.push({endpoint,method:options.method,body:options.body});return {ok:true,status:200,json:async()=>({data:fixture[endpoint]??[],meta:{total:1}})};};
w.eval(code);
const tick=()=>new Promise(r=>setTimeout(r,50));
const find=(text)=>[...w.document.querySelectorAll('button')].find(b=>b.textContent.trim()===text);
(async()=>{
await tick();await tick();
assert.equal(w.document.querySelectorAll('.sidebar nav button').length,11);
for(const button of w.document.querySelectorAll('.sidebar nav button')) {assert.equal(button.querySelectorAll('svg.admin-nav-icon').length,1);assert(!button.querySelector('img'));}
const labels=['运营概览','用户管理','活动管理','举报治理','安全警报','分类配置','地区管理','系统头像','图标素材','审计日志','功能开关'];
for(const label of labels){const nav=[...w.document.querySelectorAll('.sidebar nav button')].find(b=>b.textContent.includes(label));assert(nav,label);nav.click();await tick();await tick();assert.equal(w.document.querySelector('.topbar h1').textContent,label);assert(!w.document.querySelector('.error-state'),`Resource error ${label}`);assert(w.document.querySelector('.page-content').textContent.trim());
if(label==='用户管理'){
find('查看详情').click();await tick();await tick();assert(w.document.querySelector('.profile-hero').textContent.includes('UI User'));
const trigger=find('暂停账号'); trigger.focus(); trigger.click();await tick();
assert(w.document.querySelector('dialog[open] textarea'));assert.equal(w.document.activeElement.tagName,'TEXTAREA');
w.document.querySelector('dialog').dispatchEvent(new w.Event('cancel',{bubbles:true,cancelable:true}));await tick();
assert(!w.document.querySelector('dialog'));assert.equal(mutations.length,0);assert.equal(w.document.activeElement,trigger);
trigger.click();await tick();w.document.querySelector('dialog textarea').value='QA reason';
w.document.querySelector('dialog form').dispatchEvent(new w.Event('submit',{bubbles:true,cancelable:true}));await tick();await tick();
assert.equal(mutations[0].endpoint,'/admin/users/ui-user/status');assert.equal(JSON.parse(mutations[0].body).reason,'QA reason');
}
if(label==='活动管理'){find('查看详情').click();await tick();await tick();assert(w.document.querySelector('.event-detail-hero').textContent.includes('UI Event'));assert(find('通过申请'));}
if(label==='图标素材'){assert(w.document.querySelector('.emoji-search input'));assert(w.document.querySelector('.emoji-tile img'));find('替换图片 / 名称').click();await tick();const form=w.document.querySelector('.dialog');assert(form.querySelector('[name=key]').readOnly);assert(!form.querySelector('[name=image]').required);find('取消').click();await tick();find('上传新图标').click();await tick();assert(w.document.querySelector('[name=image]').required);
const file=w.document.querySelector('[name=image]'); assert(file.closest('.file-picker'));assert.equal(file.name,'image');
Object.defineProperty(file,'files',{configurable:true,value:[new w.File(['png'],'blue-64.png',{type:'image/png'})]});
file.dispatchEvent(new w.Event('change',{bubbles:true}));await tick();assert(w.document.querySelector('.file-picker-name').textContent.includes('blue-64.png'));
file.form.reset();await tick();assert(w.document.querySelector('.file-picker-name').textContent.includes('尚未选择文件'));
find('取消').click();await tick();}
if(label==='分类配置'){find('＋ 新建分类').click();await tick();assert(w.document.querySelector('.category-dialog'));w.document.querySelector('.dialog-head button').click();await tick();
const before=mutations.length;find('删除').click();await tick();assert(w.document.querySelector('dialog[open]'));find('取消').click();await tick();assert.equal(mutations.length,before);
find('删除').click();await tick();find('确认').click();await tick();await tick();assert.equal(mutations.at(-1).method,'DELETE');assert.equal(mutations.at(-1).endpoint,'/admin/categories/ui-category');
}
}
assert.equal(errors.length,0,errors.join('\n'));
assert(calls.includes('/admin/users/ui-user'));assert(calls.includes('/admin/events/ui-event'));
console.log('Production React bundle: 11 live-resource pages including icon library and category binding, user/event details, application control and category dialog passed with isolated fetch fixtures. Custom prompt/confirm cancel/submit, Escape/focus restoration, file filename/reset and original mutation payloads passed. No service or network calls.');
dom.window.close();
})().catch(e=>{console.error(e);dom.window.close();process.exitCode=1;});
