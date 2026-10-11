# -*- coding: utf-8 -*-
from pathlib import Path
from html.parser import HTMLParser
from urllib.parse import urlsplit

root = Path(__file__).resolve().parent / 'dist'
class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.refs=[]; self.ids=set(); self.lang=None; self.h1=0
        self.feed(text)
    def handle_starttag(self, tag, attrs):
        a=dict(attrs)
        if tag=='html': self.lang=a.get('lang')
        if tag=='h1': self.h1+=1
        if 'id' in a: self.ids.add(a['id'])
        for key in ('href','src'):
            if key in a: self.refs.append(a[key])

pages={p.name:Page(p.read_text(encoding='utf-8')) for p in root.glob('*.html')}
assert len(pages)==15, len(pages)
for name,p in pages.items():
    assert p.lang in ('zh-CN','en','ko') and p.h1==1, name
    for ref in p.refs:
        u=urlsplit(ref)
        if u.scheme or u.netloc: continue
        target=u.path or name
        assert (root/target).is_file(), (name,ref)
        if u.fragment: assert u.fragment in pages[target].ids, (name,ref)
    for suffix in ('','-en','-ko'):
        base=name.replace('-en.html','.html').replace('-ko.html','.html')[:-5]
        assert base+suffix+'.html' in p.refs, (name,suffix)
privacy_expectations={
    'privacy.html':('2026年10月20日','个人运营者','个人信息处理明细','处理委托','境外转移'),
    'privacy-en.html':('October 20, 2026','individual','Processing details','Processors','Overseas transfers'),
    'privacy-ko.html':('2026년 10월 20일','개인','개인정보 처리 내역','개인정보 처리위탁','개인정보 국외 이전'),
}
for name,expected in privacy_expectations.items():
    text=(root/name).read_text(encoding='utf-8')
    for value in expected:
        assert value in text,(name,value)
print('PASS: 15 pages, language metadata, headings, local assets, page/anchor links and same-page language switching.')
