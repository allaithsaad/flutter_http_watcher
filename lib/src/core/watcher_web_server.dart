import 'dart:convert';
import 'dart:io';
import '../model/network_log.dart';

class WatcherWebServer {
  HttpServer? _server;
  String? _url;
  String? _lastError;

  String? get url => _url;
  bool get isRunning => _server != null;
  String? get lastError => _lastError;
  bool get isLoopback => _url != null && _url!.contains('://127.0.0.1');

  Future<String?> start(List<NetworkLog> Function() getLogs) async {
    if (_server != null) return _url;
    _lastError = null;
    try {
      final ip = await _localIp();
      _server = await HttpServer.bind(ip, 9742, shared: true);
      _url = 'http://$ip:9742';
      _serve(getLogs);
      return _url;
    } catch (e) {
      _lastError = e.toString();
      return null;
    }
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    _url = null;
  }

  void _serve(List<NetworkLog> Function() getLogs) {
    _server?.listen((req) async {
      if (req.uri.path == '/api/logs') {
        final data = getLogs()
            .map((l) => {
                  'method': l.method,
                  'url': l.url,
                  'statusCode': l.statusCode,
                  'durationMs': l.durationMs,
                  'timestamp': l.timestamp.toIso8601String(),
                  'requestHeaders': l.requestHeaders,
                  'requestBody': l.requestBody?.toString(),
                  'responseBody': l.responseBody,
                })
            .toList();
        req.response
          ..headers.contentType = ContentType.json
          ..headers.add('Access-Control-Allow-Origin', '*')
          ..write(jsonEncode(data));
        await req.response.close();
      } else {
        req.response
          ..headers.contentType = ContentType.html
          ..write(_html);
        await req.response.close();
      }
    });
  }

  Future<String> _localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLinkLocal: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  // ignore: long-string
  static const _html = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>HTTP Watcher</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{background:#0d0d1a;color:#fff;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;font-size:13px}
header{background:#1a1a2e;padding:12px 16px;display:flex;align-items:center;gap:10px;position:sticky;top:0;z-index:10;border-bottom:1px solid #2a2a3e}
h1{font-size:15px;font-weight:600;flex:1}
#dot{width:8px;height:8px;border-radius:50%;background:#4caf50;flex-shrink:0}
#dot.off{background:#f44336}
#count{font-size:12px;color:rgba(255,255,255,.4);white-space:nowrap}
#filters{background:#1a1a2e;padding:10px 16px;border-bottom:1px solid #2a2a3e;display:flex;flex-direction:column;gap:8px;position:sticky;top:49px;z-index:9}
#search{background:#0d0d1a;border:1px solid #2a2a3e;border-radius:8px;padding:8px 12px;color:#fff;font-size:13px;width:100%;outline:none}
#search:focus{border-color:#61afef}
#search::placeholder{color:rgba(255,255,255,.3)}
.chips{display:flex;gap:6px;flex-wrap:wrap}
.chip{background:transparent;border:1px solid #2a2a3e;border-radius:20px;padding:4px 12px;color:rgba(255,255,255,.4);font-size:12px;cursor:pointer}
.chip:hover{border-color:rgba(255,255,255,.4);color:#fff}
.chip.on{color:#fff;background:rgba(97,175,239,.12);border-color:#61afef}
.mGET.on{border-color:#61afef;color:#61afef;background:rgba(97,175,239,.1)}
.mPOST.on{border-color:#98c379;color:#98c379;background:rgba(152,195,121,.1)}
.mPUT.on{border-color:#e5c07b;color:#e5c07b;background:rgba(229,192,123,.1)}
.mDELETE.on{border-color:#e06c75;color:#e06c75;background:rgba(224,108,117,.1)}
.s2xx.on{border-color:#4caf50;color:#4caf50;background:rgba(76,175,80,.1)}
.s4xx.on{border-color:#ff9800;color:#ff9800;background:rgba(255,152,0,.1)}
.s5xx.on{border-color:#f44336;color:#f44336;background:rgba(244,67,54,.1)}
.serr.on{border-color:#9e9e9e;color:#9e9e9e;background:rgba(158,158,158,.1)}
table{width:100%;border-collapse:collapse}
th{background:#1a1a2e;padding:9px 16px;text-align:left;font-weight:500;color:rgba(255,255,255,.4);border-bottom:1px solid #2a2a3e;white-space:nowrap}
td{padding:9px 16px;border-bottom:1px solid #1c1c2e;vertical-align:middle}
tr:hover td{background:#1a1a2e;cursor:pointer}
.m{font-weight:700;font-size:11px}
.GET{color:#61afef}.POST{color:#98c379}.PUT{color:#e5c07b}.DELETE{color:#e06c75}.OTHER{color:rgba(255,255,255,.5)}
.path{color:#fff}.host{color:rgba(255,255,255,.3);font-size:11px;margin-top:2px}
.st{font-weight:700}
.s2{color:#4caf50}.s4{color:#ff9800}.s5{color:#f44336}.se{color:#9e9e9e}
.dur{color:rgba(255,255,255,.3);font-size:11px}
.empty{text-align:center;padding:80px 20px;color:rgba(255,255,255,.25)}
.modal{display:none;position:fixed;inset:0;background:rgba(0,0,0,.75);z-index:100;padding:20px;overflow-y:auto}
.modal.open{display:block}
.box{background:#1a1a2e;border-radius:12px;max-width:720px;width:100%;margin:0 auto}
.mhdr{padding:14px 18px;border-bottom:1px solid #2a2a3e;display:flex;align-items:center;gap:10px;position:sticky;top:0;background:#1a1a2e;z-index:1}
.mtitle{flex:1;font-size:13px;font-weight:600;word-break:break-all}
.xbtn{background:none;border:none;color:rgba(255,255,255,.4);cursor:pointer;font-size:18px;padding:4px;line-height:1}
.sec{border-bottom:1px solid #2a2a3e}
.sec:last-child{border-bottom:none}
.shdr{padding:10px 18px 6px;display:flex;align-items:center;gap:6px}
.slbl{font-size:10px;color:rgba(255,255,255,.35);text-transform:uppercase;letter-spacing:.8px;flex:1}
.cbtn{background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.1);border-radius:6px;padding:3px 10px;color:rgba(255,255,255,.5);font-size:11px;cursor:pointer;white-space:nowrap;transition:all .15s}
.cbtn:hover{background:rgba(255,255,255,.1);color:#fff}
.cbtn.ok{color:#4caf50!important;border-color:#4caf50!important}
pre{background:#0d0d1a;margin:0 18px 14px;border-radius:8px;padding:12px;font-size:12px;white-space:pre-wrap;word-break:break-all;color:#90ee90;max-height:280px;overflow:auto;line-height:1.5}
pre.curl{color:#61afef}
</style>
</head>
<body>
<header>
  <div id="dot"></div>
  <h1>HTTP Watcher</h1>
  <span id="count">0 requests</span>
</header>
<div id="filters">
  <input id="search" type="text" placeholder="Search URL, method, status…" oninput="applyF()">
  <div class="chips" id="mc">
    <button class="chip on" onclick="setM(null,this)">All</button>
    <button class="chip mGET" onclick="setM('GET',this)">GET</button>
    <button class="chip mPOST" onclick="setM('POST',this)">POST</button>
    <button class="chip mPUT" onclick="setM('PUT',this)">PUT</button>
    <button class="chip mDELETE" onclick="setM('DELETE',this)">DELETE</button>
  </div>
  <div class="chips" id="sc">
    <button class="chip on" onclick="setS(null,this)">All</button>
    <button class="chip s2xx" onclick="setS('2xx',this)">2xx</button>
    <button class="chip s4xx" onclick="setS('4xx',this)">4xx</button>
    <button class="chip s5xx" onclick="setS('5xx',this)">5xx</button>
    <button class="chip serr" onclick="setS('err',this)">Error</button>
  </div>
</div>
<div id="root"><div class="empty">Waiting for requests…</div></div>

<div class="modal" id="modal">
  <div class="box">
    <div class="mhdr">
      <div class="mtitle" id="mtitle"></div>
      <button class="xbtn" onclick="closeM()">&#x2715;</button>
    </div>
    <div id="mbody"></div>
  </div>
</div>

<script>
var all=[],logs=[],mf=null,sf=null;
var BS=String.fromCharCode(92),NL=String.fromCharCode(10);

function mc(m){return{GET:1,POST:1,PUT:1,DELETE:1}[m]?'m '+m:'m OTHER';}
function sc(s){if(!s||s===0)return'st se';if(s>=500)return'st s5';if(s>=400)return'st s4';if(s>=200)return'st s2';return'st se';}
function pj(s){try{return JSON.stringify(JSON.parse(s),null,2);}catch(e){return s||'';}}
function esc(s){return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}

function toCurl(l){
  var sep=' '+BS+NL+'  ';
  var c='curl -X '+l.method+' "'+l.url+'"';
  if(l.requestHeaders){for(var k in l.requestHeaders){c+=sep+'-H "'+k+': '+l.requestHeaders[k]+'"';}}
  if(l.requestBody){c+=sep+'-d \''+l.requestBody+'\'';}
  return c;
}

function copy(text,btn){
  var done=function(){var o=btn.textContent;btn.textContent='Copied!';btn.classList.add('ok');setTimeout(function(){btn.textContent=o;btn.classList.remove('ok');},1500);};
  if(navigator.clipboard){navigator.clipboard.writeText(text).then(done).catch(function(){fb(text);done();});}
  else{fb(text);done();}
}
function fb(t){var x=document.createElement('textarea');x.value=t;document.body.appendChild(x);x.select();document.execCommand('copy');document.body.removeChild(x);}

function setM(v,btn){mf=v;document.querySelectorAll('#mc .chip').forEach(function(b){b.classList.remove('on');});btn.classList.add('on');applyF();}
function setS(v,btn){sf=v;document.querySelectorAll('#sc .chip').forEach(function(b){b.classList.remove('on');});btn.classList.add('on');applyF();}
function applyF(){
  var q=document.getElementById('search').value.toLowerCase();
  logs=all.filter(function(l){
    if(mf&&l.method!==mf)return false;
    if(sf){
      var s=l.statusCode;
      if(sf==='2xx'&&!(s>=200&&s<300))return false;
      if(sf==='4xx'&&!(s>=400&&s<500))return false;
      if(sf==='5xx'&&!(s>=500))return false;
      if(sf==='err'&&(s&&s!==0))return false;
    }
    if(q&&!(l.url||'').toLowerCase().includes(q)&&!l.method.toLowerCase().includes(q)&&!String(l.statusCode||'').includes(q))return false;
    return true;
  });
  renderT();
}
function renderT(){
  var n=all.length,f=logs.length;
  document.getElementById('count').textContent=n+' request'+(n!==1?'s':'')+(f!==n?' ('+f+' shown)':'');
  if(!f){document.getElementById('root').innerHTML='<div class="empty">'+(n?'No matching requests':'No requests yet')+'</div>';return;}
  var t='<table><thead><tr><th>Method</th><th>URL</th><th>Status</th><th>Duration</th></tr></thead><tbody>';
  for(var i=0;i<f;i++){
    var l=logs[i],url=l.url||'',path=url,host='',idx=all.indexOf(l);
    try{var u=new URL(url);path=u.pathname+u.search;host=u.host;}catch(e){}
    t+='<tr onclick="show('+idx+')">';
    t+='<td><span class="'+mc(l.method)+'">'+l.method+'</span></td>';
    t+='<td><div class="path">'+esc(path)+'</div><div class="host">'+esc(host)+'</div></td>';
    t+='<td><span class="'+sc(l.statusCode)+'">'+(l.statusCode||'ERR')+'</span></td>';
    t+='<td><span class="dur">'+l.durationMs+'ms</span></td></tr>';
  }
  t+='</tbody></table>';
  document.getElementById('root').innerHTML=t;
}

function show(i){
  var l=all[i];if(!l)return;
  document.getElementById('mtitle').textContent=l.method+' '+l.url;
  var h='';
  var sum='URL:      '+l.url+NL+'Method:   '+l.method+NL+'Status:   '+(l.statusCode||'Error')+NL+'Duration: '+l.durationMs+'ms'+NL+'Time:     '+new Date(l.timestamp).toLocaleString();
  h+='<div class="sec"><div class="shdr"><span class="slbl">Summary</span>';
  h+='<button class="cbtn" onclick="copySum('+i+',this)">Copy</button>';
  h+='</div><pre>'+esc(sum)+'</pre></div>';
  h+='<div class="sec"><div class="shdr"><span class="slbl">cURL</span><button class="cbtn" onclick="copyCurl('+i+',this)">Copy</button></div><pre class="curl">'+esc(toCurl(l))+'</pre></div>';
  if(l.requestHeaders&&Object.keys(l.requestHeaders).length){
    var hs='';for(var k in l.requestHeaders){hs+=k+': '+l.requestHeaders[k]+NL;}
    h+='<div class="sec"><div class="shdr"><span class="slbl">Request Headers</span><button class="cbtn" onclick="copyRH('+i+',this)">Copy</button></div><pre>'+esc(hs.trim())+'</pre></div>';
  }
  if(l.requestBody){
    h+='<div class="sec"><div class="shdr"><span class="slbl">Request Body</span><button class="cbtn" onclick="copyRB('+i+',this)">Copy</button></div><pre>'+esc(pj(l.requestBody))+'</pre></div>';
  }
  h+='<div class="sec"><div class="shdr"><span class="slbl">Response Body</span><button class="cbtn" onclick="copyResp('+i+',this)">Copy</button></div><pre>'+esc(pj(l.responseBody||''))+'</pre></div>';
  document.getElementById('mbody').innerHTML=h;
  document.getElementById('modal').classList.add('open');
}
function copySum(i,btn){var l=all[i];var s='URL:      '+(l.url||'')+NL+'Method:   '+(l.method||'')+NL+'Status:   '+(l.statusCode||'Error')+NL+'Duration: '+(l.durationMs||0)+'ms'+NL+'Time:     '+new Date(l.timestamp).toLocaleString();copy(s,btn);}
function copyCurl(i,btn){copy(toCurl(all[i]),btn);}
function copyRH(i,btn){var l=all[i],s='';for(var k in l.requestHeaders){s+=k+': '+l.requestHeaders[k]+NL;}copy(s.trim(),btn);}
function copyRB(i,btn){copy(pj(all[i].requestBody),btn);}
function copyResp(i,btn){copy(pj(all[i].responseBody||''),btn);}
function closeM(){document.getElementById('modal').classList.remove('open');}
document.getElementById('modal').addEventListener('click',function(e){if(e.target===this)closeM();});

async function poll(){
  try{var r=await fetch('/api/logs');var d=await r.json();all=d;applyF();document.getElementById('dot').className='';}
  catch(e){document.getElementById('dot').className='off';}
}
poll();setInterval(poll,3000);
</script>
</body>
</html>''';
}
