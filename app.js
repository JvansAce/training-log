/* ============================================================
   Brand New Body — training log
   Data lives in localStorage under STORE_KEY. Export from Setup
   to move between devices or keep a backup.
   ============================================================ */

const STORE_KEY = 'bnb.v1';
const CHECK = '<svg viewBox="0 0 12 12" fill="none" stroke="#141824" stroke-width="2.2" stroke-linecap="round"><path d="M2 6.3 4.6 9 10 3"/></svg>';

/* ---------------- plan ---------------- */
const SCHEDULE = {
  1:{label:'MO',color:'#4C7BE8',title:'Tennis',tag:'Athletic day',
     note:'Your conditioning is covered. No lifting today. Carb meal 2–3h before, shake after.',
     items:[{n:'Dynamic warm-up',p:'leg swings · lunge w/ rotation · shoulder circles · 3 short sprints'},
            {n:'Tennis',p:'play'},
            {n:'Core finisher (optional)',p:'hanging leg raises 3×12 · plank 3×45s'},
            {n:'Post-match shake',p:'30g whey + 300ml milk + banana'}]},
  2:{label:'TU',color:'#E23B3B',title:'Upper · Strength',tag:'Rest 2–3 min',restSec:150,
     note:'The heavy day. Add weight or a rep whenever you hit the top of the range.',
     items:[{n:'Band pull-aparts + arm circles',p:'warm-up 2×15'},
            {n:'Weighted pull-ups',p:'4 × 5–8 — add weight at 8',id:'wpullup'},
            {n:'Incline DB press',p:'4 × 8–10',id:'incline'},
            {n:'Barbell or DB row',p:'4 × 8–10',id:'row'},
            {n:'Overhead press',p:'3 × 8–10',id:'ohp'},
            {n:'Dips',p:'3 × to 2 reps shy of failure',id:'dips'}]},
  3:{label:'WE',color:'#E23B3B',title:'Lower · Strength',tag:'Rest 2–3 min',restSec:150,
     note:'If Monday tennis left you wrecked, swap this with Tuesday.',
     items:[{n:'Leg swings · hip circles · 90/90',p:'warm-up 5 min'},
            {n:'Squat or trap bar deadlift',p:'4 × 5–8',id:'squat'},
            {n:'Romanian deadlift',p:'3 × 8–10',id:'rdl'},
            {n:'Bulgarian split squat',p:'3 × 10 / leg',id:'bss'},
            {n:'Calf raises',p:'3 × 15',id:'calf'},
            {n:'Hanging leg raises',p:'3 × 12',id:'hlr'}]},
  4:{label:'TH',color:'#D9A13B',title:'Easy Cardio',tag:'Zone 2 only',
     note:'Conversational pace. If WHOOP recovery is red, take the full rest instead — this is the first thing to drop.',
     items:[{n:'Zone 2',p:'20–35 min easy jog, bike or brisk hike'},
            {n:'Daily mobility',p:'see below'}]},
  5:{label:'FR',color:'#E23B3B',title:'Upper · Volume',tag:'Rest 60–90s',restSec:75,
     note:'Chase the pump here. Lateral raises are what make the suit fit.',
     items:[{n:'Band pull-aparts',p:'warm-up 2×15'},
            {n:'Pull-ups',p:'4 × max reps',id:'pullup'},
            {n:'Flat DB press',p:'4 × 10–12',id:'flat'},
            {n:'Cable or band row',p:'3 × 12',id:'crow'},
            {n:'Lateral raises',p:'4 × 15',id:'lat'},
            {n:'Curls + triceps',p:'3 × 12 each',id:'arms'}]},
  6:{label:'SA',color:'#E23B3B',title:'Lower + Pyramid',tag:'Treat it as a session',
     note:'The pyramid is a full session element, not an add-on. Every other week wear the vest instead of climbing higher.',
     items:[{n:'Front or goblet squat',p:'4 × 8',id:'fsquat'},
            {n:'Box jumps',p:'4 × 6 explosive, full rest',id:'boxjump'},
            {n:'PYRAMID',p:'',id:'pyramid'}]},
  0:{label:'SU',color:'#868FA6',title:'Full Rest',tag:'Growth happens here',
     note:'Nothing structured. Walk, stretch, eat. Long mobility is the only box worth ticking.',
     items:[{n:'Long mobility (20 min)',p:'deep squat · couch stretch · thoracic rotations · pigeon · calves'},
            {n:'Weekly weigh-in average check',p:'see Progress'}]}
};
const ORDER = [1,2,3,4,5,6,0];

const MOBILITY = [
  {n:'Deep squat hold',p:'2 × 1 min'},
  {n:'Couch stretch',p:'1 min / side'},
  {n:'Shoulder dislocates',p:'2 × 10, band or broomstick'},
  {n:'Dead hang',p:'2 × 30–45s'}
];

const MEALS = [
  {h:'Breakfast',kc:'~750 kcal',p:'100g oats + 400ml whole milk, banana, 30g nuts, 2 eggs'},
  {h:'Lunch',kc:'~800 kcal',p:'150–180g chicken/beef/fish, 120g rice dry, veg + 1 EL olive oil'},
  {h:'Post-workout shake',kc:'~400 kcal',p:'30g whey + 300ml whole milk + banana'},
  {h:'Dinner',kc:'~800 kcal',p:'Protein + big carb portion + veg. Vollkornbrot with Quark works too.'},
  {h:'Evening',kc:'~450 kcal',p:'250g Magerquark with honey/berries + handful of nuts'}
];

const ADDINS = [
  'Weighted vest hike, 60–90 min',
  'Handstand practice, 5 min after upper days',
  'Rope climbs or towel pull-ups',
  'Bouldering session',
  'Sprints: 6–8 × 60m, full rest',
  '"Murph light" with vest — quarterly benchmark'
];

/* ---------------- state ---------------- */
const iso = d => d.toLocaleDateString('en-CA');
let todayISO = iso(new Date());
let todayDow = new Date().getDay();
const DEFAULTS = {startDate:todayISO, weights:[], logs:{}, lifts:{}, pyramidCap:6, calAdjust:0, updatedAt:0};
let S = structuredClone(DEFAULTS);
let viewing = todayDow;
let editingDate = null;   // set to an ISO date to back-fill a past day instead of today

/* An installed PWA is resumed, not reloaded — it can sit open across
   midnight for days. todayISO/todayDow are read by every write path
   (dayLog, lift logging, weigh-in save), so if they never advance,
   everything typed after midnight silently lands on yesterday's date.
   Called before every render and on a slow interval/visibility check. */
function syncClock(){
  const t = iso(new Date());
  if (t === todayISO) return false;
  const newDow = new Date().getDay();
  if (viewing === todayDow) viewing = newDow;   // was following "today" — keep following it
  todayISO = t;
  todayDow = newDow;
  return true;
}

function load(){
  try{
    const raw = localStorage.getItem(STORE_KEY);
    if(raw){
      S = Object.assign(structuredClone(DEFAULTS), JSON.parse(raw));
      // A parsed-but-wrong-shaped field (e.g. {"weights":null} from a
      // half-written save) would otherwise throw on the line below, outside
      // this try — and since that runs before the first render(), the app
      // never draws anything again until someone clears storage by hand.
      if(!Array.isArray(S.weights)) S.weights = [];
      if(!S.logs || typeof S.logs !== 'object') S.logs = {};
      if(!S.lifts || typeof S.lifts !== 'object') S.lifts = {};
    }
  }catch(e){
    toast('Saved data could not be read. Starting fresh.');
    S = structuredClone(DEFAULTS);
  }
  if(!S.weights.length) S.weights = [{d:todayISO, kg:79}];
}
function save(){
  S.updatedAt = Date.now();
  try{ localStorage.setItem(STORE_KEY, JSON.stringify(S)); }
  catch(e){ toast('Storage is full or blocked — changes will not persist.'); }
  Sync.schedule(()=>S, adoptMerged);
}

/* The server returns the merged record. Adopt it, but never yank the page
   out from under someone mid-entry — defer the redraw until they're done. */
let deferredMerge = null;
function adoptMerged(merged){
  if(JSON.stringify(merged)===JSON.stringify(stripLocal(S))){ updateFoot(); return; }
  const busy = document.activeElement && document.activeElement.tagName==='INPUT';
  if(busy){ deferredMerge = merged; updateFoot(); return; }
  S = Object.assign(structuredClone(DEFAULTS), merged);
  try{ localStorage.setItem(STORE_KEY, JSON.stringify(S)); }catch(e){}
  render();
}
function stripLocal(o){
  const {startDate,weights,logs,lifts,pyramidCap,calAdjust,updatedAt}=o;
  return {updatedAt:updatedAt||0,startDate,pyramidCap,calAdjust,weights,logs,lifts};
}
document.addEventListener('focusout',()=>{
  if(!deferredMerge) return;
  const m=deferredMerge; deferredMerge=null;
  setTimeout(()=>adoptMerged(m),150);
});
let toastTimer;
function toast(msg){
  const el=document.getElementById('toast');
  el.textContent=msg; el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer=setTimeout(()=>el.classList.remove('show'),2800);
}

/* ---------------- Cloudflare Access identity ----------------
   When the site sits behind Access, Cloudflare serves the signed-in
   user's identity at /cdn-cgi/access/get-identity. Off Access (local
   file, GitHub Pages) the request fails and the app runs unchanged. */
let identity = null;

async function fetchIdentity(){
  try{
    const r = await fetch('/cdn-cgi/access/get-identity',{cache:'no-store'});
    if(!r.ok) return null;
    const j = await r.json();
    return j && j.email ? j : null;
  }catch(e){ return null; }
}

/* ---------------- helpers ---------------- */
function dayLog(d=editingDate||todayISO){
  if(!S.logs[d]) S.logs[d]={done:[],fuel:false,mob:[],note:''};
  const l=S.logs[d];
  l.done=l.done||[]; l.mob=l.mob||[]; l.note=l.note||'';
  return l;
}
function fuel(dow){
  const rest = dow===0 || dow===4;
  const cal=(rest?2900:3200)+(S.calAdjust||0), pro=170, fat=rest?90:95;
  return {cal,pro,fat,carb:Math.round((cal-pro*4-fat*9)/4),rest};
}
const avg = a => a.length ? a.reduce((x,y)=>x+y,0)/a.length : null;
const sortW = () => [...S.weights].sort((a,b)=>a.d<b.d?-1:1);
// A device that adopts a merged server state with zero weigh-ins anywhere
// (e.g. a brand-new account synced before its first weigh-in) has no
// weight to average — null rather than NaN so callers can show a placeholder.
function latestAvg(){ const w=sortW().slice(-7); return w.length ? avg(w.map(x=>x.kg)) : null; }
const fmtAvg = () => { const a=latestAvg(); return a==null ? '–' : a.toFixed(1); };
function trend(){
  const w=sortW();
  if(w.length<2) return null;
  const days=(new Date(w[w.length-1].d)-new Date(w[0].d))/864e5;
  if(days<7) return null;
  return {rate:((avg(w.slice(-7).map(x=>x.kg))-avg(w.slice(0,7).map(x=>x.kg)))/days)*30, days};
}
function verdict(){
  const t=trend();
  if(!t) return {cls:'',html:'Log 7+ days of weigh-ins to see your rate.'};
  const r=t.rate, cls = r<0.35?'slow':r>1.0?'fast':'ok';
  const tail = cls==='slow' ? 'Below target — add 200 kcal (more milk, bigger rice portion).'
             : cls==='fast' ? 'Faster than a lean bulk needs. Hold calories steady.'
             : 'On target for a lean bulk.';
  return {cls, html:`<b>${r>0?'+':''}${r.toFixed(2)} kg / month</b> over ${Math.round(t.days)} days. ${tail}`};
}
const weeksIn = () => Math.max(0,Math.floor((new Date(todayISO)-new Date(S.startDate))/6048e5));
const fmtSet = e => `${e.kg?e.kg+' kg':'BW'} × ${e.reps}`;
const beats = (a,b) => ((a.kg||0)*1000+a.reps) > ((b.kg||0)*1000+b.reps);
const escapeHtml = s => String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
const MAX_SETS = 5;

// A day's lift entry used to be one flat {d,kg,reps}. It's now {d,sets:[...]}
// so a "4 x 8" prescription can actually be logged as four sets — this
// reads either shape so nobody's history breaks on the day this shipped.
function setsOf(entry){
  if(!entry) return [];
  if(Array.isArray(entry.sets)) return entry.sets;
  if(entry.reps!=null) return [{kg:entry.kg, reps:entry.reps}];
  return [];
}
function bestSet(entry){
  const sets=setsOf(entry);
  return sets.length ? sets.reduce((a,b)=>beats(b,a)?b:a) : null;
}

function itemsFor(dow){
  return SCHEDULE[dow].items.map(it=>{
    if(it.n!=='PYRAMID') return it;
    return {...it, n:`Holland pyramid — to round ${S.pyramidCap}`,
      p:'1 pull-up · 2 dips · 3 push-ups · 4 sit-ups · 5 squats, climbing each round'};
  });
}
function refText(id,activeDate){
  const h=S.lifts[id]||[];
  const mine=h.find(x=>x.d===activeDate);
  const last=[...h].filter(x=>x.d!==activeDate).sort((a,b)=>a.d<b.d?-1:1).pop();
  const fmtAll=e=>setsOf(e).map(fmtSet).join(' · ');
  if(!last) return mine?`logged ${fmtAll(mine)}`:'first entry — this becomes your benchmark';
  let s=`last ${fmtAll(last)} · ${last.d.slice(5)}`;
  const mb=bestSet(mine), lb=bestSet(last);
  if(mb&&lb&&beats(mb,lb)) s+=' ▲ beaten';
  return s;
}
function setRowHtml(id,i,s){
  return `<div class="setrow" data-set="${i}">
    <span class="setno">${i+1}</span>
    <input type="number" step="0.5" min="0" max="500" inputmode="decimal" placeholder="kg"
      value="${s&&s.kg!=null?s.kg:''}" data-skg="${id}:${i}" aria-label="Set ${i+1} weight kg">
    <span class="mult">×</span>
    <input type="number" step="1" min="1" max="500" inputmode="numeric" placeholder="reps"
      value="${s&&s.reps!=null?s.reps:''}" data-srep="${id}:${i}" aria-label="Set ${i+1} reps">
  </div>`;
}
function logRow(id,canEdit,activeDate){
  if(!canEdit) return `<div class="logref">${refText(id,activeDate)}</div>`;
  const mine=(S.lifts[id]||[]).find(x=>x.d===activeDate);
  const mySets=setsOf(mine);
  const shown=Math.max(1,mySets.length);
  const rows=[];
  for(let i=0;i<shown;i++) rows.push(setRowHtml(id,i,mySets[i]));
  return `<div class="logrow" data-log="${id}">
    <div class="setrows">${rows.join('')}</div>
    ${shown<MAX_SETS?`<button type="button" class="addset" data-addset="${id}">+ set</button>`:''}
    <div class="logref">${refText(id,activeDate)}</div>
  </div>`;
}

/* ---------------- charts ---------------- */
function spark(){
  const w=sortW().slice(-30);
  if(w.length<2) return '';
  const v=w.map(x=>x.kg), lo=Math.min(...v)-0.4, hi=Math.max(...v)+0.4, W=100,H=40;
  const pts=v.map((k,i)=>[(i/(v.length-1))*W, H-((k-lo)/(hi-lo))*H]);
  const line=pts.map((p,i)=>`${i?'L':'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ');
  return `<svg class="spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true">
    <path d="${line} L${W} ${H} L0 ${H} Z" fill="rgba(226,59,59,.12)"/>
    <path d="${line}" fill="none" stroke="#E23B3B" stroke-width="1.2" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>
    <circle cx="${pts.at(-1)[0]}" cy="${pts.at(-1)[1]}" r="1.6" fill="#EDE7DB"/></svg>`;
}
function weightChart(){
  const w=sortW();
  if(w.length<3) return `<div class="empty">Log a few mornings and the curve shows up here.</div>`;
  const v=w.map(x=>x.kg), lo=Math.floor(Math.min(...v)-1), hi=Math.ceil(Math.max(...v)+1);
  const W=100,H=100;
  const y=k=>H-((k-lo)/(hi-lo))*H;
  const pts=v.map((k,i)=>[(i/(v.length-1))*W, y(k)]);
  const line=pts.map((p,i)=>`${i?'L':'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ');
  return `<svg class="chart" viewBox="-2 -6 108 118" aria-label="Body weight over time">
    <line x1="0" y1="${y(lo)}" x2="100" y2="${y(lo)}" stroke="#2E3750" stroke-width=".5"/>
    <line x1="0" y1="${y(hi)}" x2="100" y2="${y(hi)}" stroke="#2E3750" stroke-width=".5"/>
    <text class="axis" x="0" y="${y(hi)-2}">${hi} kg</text>
    <text class="axis" x="0" y="${y(lo)+7}">${lo} kg</text>
    <path d="${line} L100 ${H} L0 ${H} Z" fill="rgba(226,59,59,.10)"/>
    <path d="${line}" fill="none" stroke="#E23B3B" stroke-width="1.4" vector-effect="non-scaling-stroke" stroke-linejoin="round"/>
    <circle cx="${pts.at(-1)[0]}" cy="${pts.at(-1)[1]}" r="2" fill="#EDE7DB"/>
    <text class="axis" x="100" y="112" text-anchor="end">${w.at(-1).d}</text>
    <text class="axis" x="0" y="112">${w[0].d}</text></svg>`;
}
function adherence(){
  const bars=[];
  for(let k=7;k>=0;k--){
    const end=new Date(); end.setDate(end.getDate()-k*7);
    const start=new Date(end); start.setDate(start.getDate()-6);
    let sessions=0;
    for(let d=new Date(start); d<=end; d.setDate(d.getDate()+1)){
      const l=S.logs[iso(d)];
      // Thu (cardio) and Sun (rest) only have 2 items — a flat >=3 makes
      // them mathematically impossible to count as a session ever.
      const need=Math.min(3, SCHEDULE[d.getDay()].items.length);
      if(l&&l.done&&l.done.length>=need) sessions++;
    }
    bars.push(sessions);
  }
  if(!bars.some(b=>b>0)) return `<div class="empty">Complete a session and your weekly consistency lands here.</div>`;
  const W=100,H=46,bw=W/bars.length;
  return `<svg class="chart" style="height:96px" viewBox="-1 -4 102 60" aria-label="Sessions completed per week">
    ${bars.map((b,i)=>{
      const h=(Math.min(b,6)/6)*H;
      const col = b>=4?'#4FB477':b>=2?'#D9A13B':'#2E3750';
      return `<rect x="${(i*bw+1.4).toFixed(1)}" y="${(H-h).toFixed(1)}" width="${(bw-2.8).toFixed(1)}"
        height="${Math.max(h,1).toFixed(1)}" fill="${col}" rx=".8"/>
      <text class="axis" x="${(i*bw+bw/2).toFixed(1)}" y="${H+7}" text-anchor="middle">${b}</text>`}).join('')}
    <text class="axis" x="0" y="${H+15}">8 weeks ago</text>
    <text class="axis" x="100" y="${H+15}" text-anchor="end">this week</text></svg>`;
}

/* ---------------- WHOOP display ---------------- */
function whoopBadge(){
  const w = Whoop.peek();
  if (!w || !w.connected) return '';   // not connected, or nothing fetched yet — stay quiet

  const rec = w.recovery, scored = rec && rec.state === 'SCORED';
  const score = scored ? rec.score : null;
  const cls = score == null ? '' : Whoop.band(score);
  const recLabel = score != null ? `${score}%`
    : (rec && rec.state === 'PENDING_SCORE') ? 'not scored yet'
    : 'no data yet today';

  const strain = w.strain && w.strain.state === 'SCORED' && w.strain.value != null
    ? w.strain.value.toFixed(1) : '–';
  const sleepPct = w.sleep && w.sleep.state === 'SCORED' && w.sleep.performance_pct != null
    ? w.sleep.performance_pct + '%' : '–';
  const hrv = rec && rec.hrv_ms != null ? Math.round(rec.hrv_ms) : '–';
  const rhr = rec && rec.rhr != null ? rec.rhr : '–';

  return `<section class="panel">
    <div class="phead"><div class="ptitle">Recovery</div>
      <div class="ptag whoop-badge ${cls}">${recLabel}</div></div>
    <div class="whoop-row">
      <div><b>${strain}</b><span>strain</span></div>
      <div><b>${sleepPct}</b><span>sleep</span></div>
      <div><b>${hrv}</b><span>hrv ms</span></div>
      <div><b>${rhr}</b><span>rhr</span></div>
    </div>
    ${cls==='low' ? `<div class="pnote">Recovery is red today. If today's session has any give in it — Thursday's cardio, the pyramid — this is the day to take it.</div>` : ''}
  </section>`;
}

function whoopSetupPanel(){
  const w = Whoop.peek();
  if (w === null){
    return `<section class="panel">
      <div class="phead"><div class="ptitle">WHOOP</div><div class="ptag">Checking…</div></div>
      <div class="pnote">Loading connection status.</div>
    </section>`;
  }
  if (!w.connected){
    const note = w.reason === 'revoked'
      ? ' The last connection was revoked from WHOOP\'s side — reconnect below.'
      : w.reason === 'unavailable'
      ? ' Could not reach the WHOOP API just now — this may just be a config or connectivity issue.'
      : '';
    return `<section class="panel">
      <div class="phead"><div class="ptitle">WHOOP</div><div class="ptag">Not connected</div></div>
      <div class="pnote">Connect WHOOP to see today's recovery, strain and sleep on the Today page — including a flag on days recovery is low.${note}</div>
      <div class="wrow"><button class="primary" id="whoopConnect">Connect WHOOP</button></div>
    </section>`;
  }
  const rec = w.recovery, scored = rec && rec.state === 'SCORED';
  const asOf = w.as_of ? new Date(w.as_of).toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'}) : '';
  return `<section class="panel">
    <div class="phead"><div class="ptitle">WHOOP</div><div class="ptag">Connected</div></div>
    <div class="pnote">Last read: ${scored ? rec.score+'% recovery' : 'no scored recovery yet today'}${asOf?', as of '+asOf:''}.</div>
    <div class="wrow"><button id="whoopRefresh">Refresh now</button>
      <button class="danger" id="whoopDisconnect">Disconnect</button></div>
  </section>`;
}

/* ---------------- rest timer ----------------
   Floating widget lives outside #view (see index.html), so it survives a
   route change while a rest is still counting down — wired once at boot,
   not inside wireToday(). */
let restTimer = { total:0, remaining:0, intervalId:null };
function renderRestTimer(){
  const el=document.getElementById('resttimer');
  if(!el) return;
  if(!restTimer.total){ el.hidden=true; return; }
  el.hidden=false;
  const r=Math.max(restTimer.remaining,0);
  el.querySelector('.rt-time').textContent=fmtMMSS(r);
  el.querySelector('.rt-bar').style.width=`${Math.max(0,(r/restTimer.total)*100)}%`;
}
function stopRestTimer(){
  clearInterval(restTimer.intervalId);
  restTimer={total:0,remaining:0,intervalId:null};
  renderRestTimer();
}
function startRestTimer(sec){
  clearInterval(restTimer.intervalId);
  restTimer={total:sec,remaining:sec,intervalId:null};
  renderRestTimer();
  restTimer.intervalId=setInterval(()=>{
    restTimer.remaining--;
    if(restTimer.remaining<=0){
      clearInterval(restTimer.intervalId);
      restTimer.intervalId=null;
      toast('Rest done.');
      if(navigator.vibrate) navigator.vibrate([200,100,200]);
    }
    renderRestTimer();
  },1000);
}

/* ---------------- views ---------------- */
const VIEWS = {};

const fmtMMSS = s => `${Math.floor(s/60)}:${String(s%60).padStart(2,'0')}`;

VIEWS.today = () => {
  const dow=new Date().getDay(), sched=SCHEDULE[viewing];
  const isToday=viewing===dow;
  // editingDate (back-filling a past day) always wins over the plain
  // "is this the weekday I'm currently previewing" check — you can only
  // ever be doing one or the other.
  const canEdit = editingDate ? true : isToday;
  const activeDate = editingDate || todayISO;
  const log = dayLog(activeDate);
  const items=itemsFor(viewing), f=fuel(viewing);
  const tlog=dayLog(todayISO), tItems=itemsFor(dow);
  const pct=tItems.length?(tlog.done.length/tItems.length)*100:0;
  const yesterday=(()=>{ const d=new Date(); d.setDate(d.getDate()-1); return iso(d); })();

  const spine=`<div class="spine">${ORDER.map((d,i)=>{
    const s=SCHEDULE[d];
    return `<button class="rib${d===dow?' today':''}${d===viewing?' viewing':''}" data-d="${d}"
      style="animation-delay:${i*45}ms" aria-label="${s.label} ${s.title}">
      ${d===dow?`<div class="rib-fill" style="height:${pct}%"></div>`:''}
      <div class="rib-dot" style="background:${s.color}"></div>
      <div class="rib-d">${s.label}</div></button>`}).join('')}</div>`;

  const backfill = editingDate ? `
    <div class="wrow backfill">
      <span class="ptag">Editing ${editingDate}</span>
      <button id="backfillDone">Back to today</button>
    </div>` : `
    <div class="wrow backfill">
      <input type="date" id="backfillPick" max="${yesterday}" aria-label="Back-fill a past day">
      <span class="ptag">forgot to log a day?</span>
    </div>`;

  const v=verdict();
  return spine + backfill + whoopBadge() + `
  <section class="panel">
    <div class="phead"><div class="ptitle">${sched.title}</div>
      <div class="ptag">${canEdit&&!editingDate?'Today':editingDate?editingDate.slice(5):sched.label+' · preview'} · ${sched.tag}</div></div>
    <div class="pnote">${sched.note}</div>
    ${items.map((it,i)=>`
      <div class="ex${canEdit&&log.done.includes(i)?' on':''}" data-ex="${i}" role="checkbox"
           tabindex="0" aria-checked="${canEdit&&log.done.includes(i)}">
        <div class="box">${CHECK}</div>
        <div class="ex-body"><div class="ex-name">${it.n}</div>
          ${it.p?`<div class="ex-pre">${it.p}</div>`:''}
          ${it.id?logRow(it.id,canEdit,activeDate):''}</div>
      </div>`).join('')}
    ${viewing===6?`<div class="wrow"><button data-cap="-1">– round</button>
      <button data-cap="1">+ round</button>
      <span class="ptag">cap ${S.pyramidCap} · build to 10</span></div>`:''}
    ${sched.restSec&&canEdit?`<div class="wrow"><button id="restStart" data-sec="${sched.restSec}">Start rest timer · ${fmtMMSS(sched.restSec)}</button></div>`:''}
    ${canEdit?`<div class="wrow" style="margin-top:14px">
      <textarea id="dayNote" rows="2" placeholder="Notes for this session (optional)">${escapeHtml(log.note||'')}</textarea>
    </div>`:log.note?`<div class="pnote"><b>Note:</b> ${escapeHtml(log.note)}</div>`:''}
    ${!isToday&&!editingDate?`<div class="wrow"><button id="backtoday">Back to today</button></div>`:''}
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Fuel</div><div class="ptag">${f.rest?'Rest day':'Training day'}</div></div>
    <div class="macros">
      <div class="macro"><b>${f.cal}</b><span>kcal</span></div>
      <div class="macro"><b>${f.pro}</b><span>protein</span></div>
      <div class="macro"><b>${f.carb}</b><span>carbs</span></div>
      <div class="macro"><b>${f.fat}</b><span>fat</span></div>
    </div>
    ${canEdit?`<div class="ex${log.fuel?' on':''}" data-fuel="1" role="checkbox" tabindex="0"
        aria-checked="${log.fuel}" style="border-top:1px solid var(--line);margin-top:14px">
      <div class="box">${CHECK}</div>
      <div class="ex-body"><div class="ex-name">Hit calories and protein today</div>
      <div class="ex-pre">90% of days beats a perfect plan you drop in October</div></div></div>`:''}
    <details><summary>Meal template</summary>
      ${MEALS.map(m=>`<div class="meal"><h4>${m.h} <span class="kc">${m.kc}</span></h4><p>${m.p}</p></div>`).join('')}
      <div class="meal"><p style="color:var(--bone)">Magerquark: 500g tub ≈ 60g protein for about €1.</p></div>
    </details>
    <div class="wrow"><button data-cal="-100">– 100 kcal</button><button data-cal="100">+ 100 kcal</button>
      <span class="ptag">adjust ${S.calAdjust>0?'+':''}${S.calAdjust}</span></div>
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Mobility</div><div class="ptag">Daily · 5–10 min</div></div>
    ${MOBILITY.map((m,i)=>`
      <div class="ex${canEdit&&log.mob.includes(i)?' on':''}" data-mob="${i}" role="checkbox"
           tabindex="0" aria-checked="${canEdit&&log.mob.includes(i)}">
        <div class="box">${CHECK}</div>
        <div class="ex-body"><div class="ex-name">${m.n}</div><div class="ex-pre">${m.p}</div></div>
      </div>`).join('')}
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Body weight</div><div class="ptag">7-day average</div></div>
    <div class="bigstat"><div class="n">${fmtAvg()}<sub> kg</sub></div>
      <div class="verdict ${v.cls}">${v.html}</div></div>
    ${spark()}
    <div class="wrow"><input type="number" id="wIn" step="0.1" min="40" max="200"
      inputmode="decimal" placeholder="this morning, kg"><button class="primary" id="wSave">Log</button></div>
    <div class="pnote">Weigh in every morning, same conditions. Judge the weekly average, never a single day.</div>
  </section>`;
};

VIEWS.week = () => {
  const wk=weeksIn(), unlocked=wk>=12, pick=ADDINS[wk%ADDINS.length];
  return `
  <section class="panel">
    <div class="phead"><div class="ptitle">The week</div><div class="ptag">4 lifts · 1 tennis · 1 cardio</div></div>
    <div class="pnote">Priority order when life gets busy: keep the four lifting days, drop Thursday cardio first, the pyramid second.</div>
    ${ORDER.map(d=>{
      const s=SCHEDULE[d];
      return `<div class="daycard"><div class="dayhead">
        <div class="daydot" style="background:${s.color}"></div>
        <div class="dayname">${s.title}</div><div class="daysub">${s.label}</div></div>
        <div class="daylist">${itemsFor(d).map(it=>
          `<div><b>${it.n}</b>${it.p?' — '+it.p:''}</div>`).join('')}</div></div>`}).join('')}
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Fuel rules</div><div class="ptag">Reference</div></div>
    <div class="daylist" style="margin-top:12px">
      <div><b>Training / tennis days</b> — 3,200 kcal · 170g protein · ~416g carbs · 95g fat</div>
      <div><b>Rest days (Thu, Sun)</b> — 2,900 kcal · 170g protein · ~352g carbs · 90g fat</div>
      <div><b>Scale flat two weeks</b> — add 200 kcal, easiest as milk and a bigger rice portion</div>
      <div><b>Protein at every meal</b> — 170g over five feedings beats two giant ones</div>
      <div><b>Tennis Mondays</b> — proper carb meal 2–3h before, shake straight after</div>
    </div>
    <details><summary>Meal template</summary>
      ${MEALS.map(m=>`<div class="meal"><h4>${m.h} <span class="kc">${m.kc}</span></h4><p>${m.p}</p></div>`).join('')}
    </details>
  </section>

  <section class="panel${unlocked?'':' locked'}">
    <div class="phead"><div class="ptitle">Add-ins</div>
      <div class="ptag">${unlocked?'Unlocked':`Week ${wk} of 12`}</div></div>
    <div class="pnote">${unlocked
      ? `Rotate one into Saturday or in place of Thursday every couple of weeks. They replace conditioning slots — never stack on top. This week: <b>${pick}</b>.`
      : `Build the base first. These open at week 12, once the four lifting days are habit and the scale is moving.`}</div>
    <div>${ADDINS.map(a=>`<span class="chip${unlocked&&a===pick?' pick':''}">${a}</span>`).join('')}</div>
  </section>`;
};

VIEWS.progress = () => {
  const v=verdict(), w=sortW();
  const gain = w.length>1 ? w.at(-1).kg - w[0].kg : 0;
  const allIds=[];
  ORDER.forEach(d=>SCHEDULE[d].items.forEach(it=>{ if(it.id&&!allIds.includes(it.id)) allIds.push(it.id); }));
  const named={};
  ORDER.forEach(d=>itemsFor(d).forEach(it=>{ if(it.id) named[it.id]=it.n; }));
  const logged=allIds.filter(id=>(S.lifts[id]||[]).length);

  return `
  <section class="panel">
    <div class="phead"><div class="ptitle">Body weight</div><div class="ptag">${w.length} weigh-ins</div></div>
    <div class="bigstat"><div class="n">${fmtAvg()}<sub> kg</sub></div>
      <div class="verdict ${v.cls}">${v.html}</div></div>
    ${weightChart()}
    <div class="pnote">Since you started: <b>${gain>0?'+':''}${gain.toFixed(1)} kg</b>. Target for a lean bulk is +0.5–0.75 kg per month.</div>
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Consistency</div><div class="ptag">Sessions per week</div></div>
    ${adherence()}
    <div class="pnote">A session counts once three items are ticked — or all of them, on the shorter cardio and rest days. Four green weeks in a row is the real win.</div>
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Top sets</div><div class="ptag">Best vs latest</div></div>
    ${logged.length?logged.map(id=>{
      const h=[...(S.lifts[id]||[])].sort((a,b)=>a.d<b.d?-1:1);
      const days=h.map(entry=>({entry, best:bestSet(entry)})).filter(x=>x.best);
      // A hand-edited or malformed imported backup could carry an entry
      // with no usable sets at all — skip the lift rather than crashing
      // the whole Progress page on an empty-array reduce.
      if(!days.length) return '';
      const best=days.reduce((a,b)=>beats(b.best,a.best)?b:a);
      const lastDay=days.at(-1);
      const isBest=lastDay===best||!beats(best.best,lastDay.best);
      const fmtAll=e=>setsOf(e).map(fmtSet).join(' · ');
      return `<div class="hist"><div class="hist-n">${named[id]||id}</div>
        <div class="hist-v"><b>${fmtAll(lastDay.entry)}</b> ${isBest?'<span class="up">▲ best</span>':''}<br>
        best ${fmtSet(best.best)} · ${h.length} entr${h.length===1?'y':'ies'}</div></div>`}).join('')
      :`<div class="empty">Log a set on the Today page and your progression appears here.</div>`}
  </section>`;
};

VIEWS.setup = () => {
  const sy=Sync.state();
  const syncCopy = {
    ok:'Your log is on the server. Sign in on any device and it arrives.',
    syncing:'Talking to the server.',
    idle:'Not synced yet this session.',
    offline:`No connection to the server, so changes are queued locally.${sy.detail?' '+sy.detail:''}`,
    unauthorized:'Your Access session lapsed. Reload to sign in again, then changes will sync.',
    unconfigured:`The API is deployed but not configured. ${sy.detail||''}`,
    absent:'No sync API on this host — this copy stores everything locally only.'
  }[sy.status] || '';

  return `
  <section class="panel">
    <div class="phead"><div class="ptitle">Account</div>
      <div class="ptag">${identity?'Signed in':'Open access'}</div></div>
    ${identity?`
      <div class="idmail">${identity.email}</div>
      <div class="pnote">${identity.name?identity.name+' · ':''}Verified by Cloudflare Access before this page loaded. Nobody reaches the site without a one-time code sent to an approved address.</div>
      <div class="wrow"><button id="signout">Sign out</button></div>`
    :`<div class="pnote">This copy is not behind Cloudflare Access — anyone with the URL can open it. That's expected when you're running it locally or on a plain static host. Once the Access application is live in front of your domain, your email shows up here.</div>`}
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Sync</div><div class="ptag">${Sync.label()}</div></div>
    <div class="pnote">${syncCopy}</div>
    <div class="pnote">Every device you sign into reads and writes the same record. Entries merge rather than overwrite, so a set logged on your phone in the garage survives a weigh-in typed on your laptop. Anything older than a few days is only ever added to, never removed.</div>
    ${sy.status==='unauthorized'?`<div class="wrow"><button class="primary" id="reauth">Reload to sign in</button></div>`
    :sy.available?`<div class="wrow"><button class="primary" id="syncNow">Sync now</button>
      <button id="pullNow">Pull from server</button></div>`:''}
  </section>

  ${whoopSetupPanel()}

  <section class="panel">
    <div class="phead"><div class="ptitle">Backup</div><div class="ptag">Move between devices</div></div>
    <div class="pnote">Data is stored in this browser only. Export a file to back it up or carry it to another device, then import it there.</div>
    <div class="wrow"><button class="primary" id="exp">Export file</button>
      <button id="impBtn">Import file</button>
      <input type="file" id="imp" accept="application/json" hidden></div>
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Start date</div><div class="ptag">Week counter</div></div>
    <div class="pnote">Currently week ${weeksIn()+1}. Set this to your real first training day — the add-ins unlock at week 12.</div>
    <div class="wrow"><input type="date" id="sd" value="${S.startDate}"><button id="sdSave">Save</button></div>
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Install</div><div class="ptag">Home screen</div></div>
    <div class="pnote">iOS: Share → Add to Home Screen. Android: menu → Install app. It then opens fullscreen and works offline in the gym.</div>
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Danger zone</div><div class="ptag">No undo</div></div>
    <div class="pnote">Deletes every weigh-in, session tick and logged set on this device, and deletes your record from the server if sync is on. A different device that's still offline and syncs later can still bring old data back — export first if that matters.</div>
    <div class="wrow"><button class="danger" id="reset">Delete all data</button></div>
  </section>`;
};

/* ---------------- wiring ---------------- */
function wireToday(){
  const dow=new Date().getDay(), isToday=viewing===dow;
  const canEdit = editingDate ? true : isToday;
  const activeDate = editingDate || todayISO;
  const log = dayLog(activeDate);
  const toggle=(arr,i)=>{const k=arr.indexOf(i); k>-1?arr.splice(k,1):arr.push(i)};
  const bind=(el,fn)=>{
    el.onclick=fn;
    el.onkeydown=e=>{if(e.key===' '||e.key==='Enter'){e.preventDefault();fn()}};
  };

  document.querySelectorAll('.rib').forEach(b=>b.onclick=()=>{
    viewing=+b.dataset.d; editingDate=null; render();
  });
  document.querySelectorAll('[data-ex]').forEach(el=>bind(el,()=>{
    if(!canEdit) return; toggle(log.done,+el.dataset.ex); save(); render();
  }));
  document.querySelectorAll('[data-mob]').forEach(el=>bind(el,()=>{
    if(!canEdit) return; toggle(log.mob,+el.dataset.mob); save(); render();
  }));
  const fu=document.querySelector('[data-fuel]');
  if(fu) bind(fu,()=>{log.fuel=!log.fuel; save(); render()});

  const dn=document.getElementById('dayNote');
  if(dn) dn.onchange=()=>{ log.note=dn.value; save(); };

  function saveSets(row,id){
    const sets=[];
    row.querySelectorAll('.setrow').forEach(sr=>{
      const kgRaw=sr.querySelector('[data-skg]').value;
      const reps=parseInt(sr.querySelector('[data-srep]').value);
      if(!isNaN(reps)&&reps>0){
        const kg=kgRaw===''?null:parseFloat(kgRaw);
        sets.push({kg:isNaN(kg)?null:kg, reps});
      }
    });
    S.lifts[id]=(S.lifts[id]||[]).filter(x=>x.d!==activeDate);
    if(sets.length) S.lifts[id].push({d:activeDate, sets});
    save();
    const ref=row.querySelector('.logref');
    if(ref) ref.textContent=refText(id,activeDate);
  }

  document.querySelectorAll('.logrow').forEach(row=>{
    row.onclick=e=>e.stopPropagation();
    row.onkeydown=e=>{e.stopPropagation(); if(e.key==='Enter') e.target.blur()};
    const id=row.dataset.log;
    row.querySelectorAll('input').forEach(inp=>{ inp.onchange=()=>saveSets(row,id); });
    const add=row.querySelector('[data-addset]');
    if(add) add.onclick=e=>{
      e.stopPropagation();
      const setrows=row.querySelector('.setrows');
      const i=setrows.children.length;
      if(i>=MAX_SETS) return;
      const wrap=document.createElement('div');
      wrap.innerHTML=setRowHtml(id,i,null);
      const newRow=wrap.firstElementChild;
      setrows.appendChild(newRow);
      newRow.querySelectorAll('input').forEach(inp=>{ inp.onchange=()=>saveSets(row,id); });
      if(i+1>=MAX_SETS) add.remove();
    };
  });

  document.querySelectorAll('[data-cap]').forEach(b=>b.onclick=()=>{
    S.pyramidCap=Math.max(3,Math.min(10,S.pyramidCap+ +b.dataset.cap)); save(); render();
  });
  document.querySelectorAll('[data-cal]').forEach(b=>b.onclick=()=>{
    S.calAdjust=(S.calAdjust||0)+ +b.dataset.cal; save(); render();
  });
  const bt=document.getElementById('backtoday');
  if(bt) bt.onclick=()=>{viewing=todayDow; render()};
  const bfd=document.getElementById('backfillDone');
  if(bfd) bfd.onclick=()=>{editingDate=null; viewing=todayDow; render()};
  const bfp=document.getElementById('backfillPick');
  if(bfp) bfp.onchange=()=>{
    const d=bfp.value; if(!d) return;
    editingDate=d;
    // Appending a local (no "Z") time forces local-midnight parsing —
    // new Date('YYYY-MM-DD') alone parses as UTC midnight and can land on
    // the wrong weekday for negative UTC offsets.
    viewing=new Date(d+'T00:00:00').getDay();
    render();
  };
  const rs=document.getElementById('restStart');
  if(rs) rs.onclick=()=>startRestTimer(+rs.dataset.sec);

  const wS=document.getElementById('wSave'), wI=document.getElementById('wIn');
  wS.onclick=()=>{
    const kg=parseFloat(wI.value);
    if(!kg||kg<40||kg>200){ wI.value=''; wI.placeholder='enter a weight in kg'; wI.focus(); return; }
    S.weights=S.weights.filter(x=>x.d!==todayISO);
    S.weights.push({d:todayISO,kg:Math.round(kg*10)/10});
    save(); render(); toast('Weight logged.');
  };
  wI.onkeydown=e=>{if(e.key==='Enter') wS.click()};
}

function wireSetup(){
  const so=document.getElementById('signout');
  if(so) so.onclick=()=>{ location.href='/cdn-cgi/access/logout'; };
  const ra=document.getElementById('reauth');
  if(ra) ra.onclick=()=>location.reload();

  const wc=document.getElementById('whoopConnect');
  if(wc) wc.onclick=()=>Whoop.connect();
  const wr=document.getElementById('whoopRefresh');
  if(wr) wr.onclick=async()=>{
    wr.disabled=true;
    await Whoop.today(true);
    render(); toast('WHOOP refreshed.');
  };
  const wd=document.getElementById('whoopDisconnect');
  if(wd) wd.onclick=async()=>{
    if(!confirm('Disconnect WHOOP? You can reconnect any time.')) return;
    await Whoop.disconnect();
    render(); toast('WHOOP disconnected.');
  };

  const sn=document.getElementById('syncNow');
  if(sn) sn.onclick=async()=>{
    sn.disabled=true; updateFoot();
    const merged=await Sync.run(S);
    sn.disabled=false;
    if(merged){ adoptMerged(merged); render(); toast('Synced.'); }
    else { render(); toast('Could not sync — see the Sync panel.'); }
  };
  const pn=document.getElementById('pullNow');
  if(pn) pn.onclick=async()=>{
    if(!confirm('Replace this device\'s log with the server copy?')) return;
    const res=await fetch('/api/state',{cache:'no-store'}).then(r=>r.ok?r.json():null).catch(()=>null);
    if(res&&res.state){
      S=Object.assign(structuredClone(DEFAULTS),res.state);
      try{ localStorage.setItem(STORE_KEY,JSON.stringify(S)); }catch(e){}
      render(); toast('Pulled from server.');
    } else toast('Nothing to pull.');
  };

  document.getElementById('exp').onclick=()=>{
    const blob=new Blob([JSON.stringify(S,null,2)],{type:'application/json'});
    const a=document.createElement('a');
    a.href=URL.createObjectURL(blob);
    a.download=`bnb-backup-${todayISO}.json`;
    a.click(); URL.revokeObjectURL(a.href);
    toast('Backup file downloaded.');
  };
  const imp=document.getElementById('imp');
  document.getElementById('impBtn').onclick=()=>imp.click();
  imp.onchange=async()=>{
    const file=imp.files[0]; if(!file) return;
    try{
      const data=JSON.parse(await file.text());
      if(!data||typeof data!=='object'||!('weights' in data)) throw 0;
      S=Object.assign(structuredClone(DEFAULTS),data);
      save(); render(); toast('Backup imported.');
    }catch(e){ toast('That file is not a valid backup.'); }
    imp.value='';
  };
  document.getElementById('sdSave').onclick=()=>{
    const d=document.getElementById('sd').value;
    if(!d) return;
    S.startDate=d; save(); render(); toast('Start date saved.');
  };
  document.getElementById('reset').onclick=async ()=>{
    if(!confirm('Delete all logged data? This cannot be undone.')) return;
    S=structuredClone(DEFAULTS);
    S.weights=[{d:todayISO,kg:79}];
    try{ localStorage.setItem(STORE_KEY, JSON.stringify(S)); }catch(e){}
    render(); toast('All data deleted.');
    // Best effort — the local wipe above is the part the person actually
    // asked for; a failure here shouldn't block that. Deliberately not a
    // save()+push: additive merge would otherwise let a stale device's old
    // record survive the delete by pushing it right back.
    if(Sync.state().available){
      try{ await fetch('/api/state', { method:'DELETE', cache:'no-store' }); }catch(e){}
    }
  };
}

function updateFoot(){
  const el=document.getElementById('foot');
  if(!el) return;
  el.textContent = `WEEK ${weeksIn()+1} · ${S.weights.length} WEIGH-INS · ${Sync.label()}`;
}

/* ---------------- router ---------------- */
function route(){
  const h=(location.hash||'#/today').replace('#/','');
  return VIEWS[h]?h:'today';
}
// Ticking a box calls save()+render() to redraw its new state; scrolling to
// top on every one of those (as opposed to an actual tab/day switch) used to
// throw you back to the masthead mid-workout. Only scroll when what's being
// shown actually changed.
let lastRenderKey = null;
function render(){
  syncClock();
  const name=route();
  const key = name==='today' ? `today:${viewing}:${editingDate||''}` : name;
  const changedView = key !== lastRenderKey;
  lastRenderKey = key;

  document.getElementById('view').innerHTML=VIEWS[name]();
  document.querySelectorAll('.tabs a').forEach(a=>
    a.classList.toggle('active',a.dataset.tab===name));

  const now=new Date();
  document.getElementById('datestamp').textContent=
    now.toLocaleDateString('en-GB',{weekday:'long',day:'numeric',month:'long',year:'numeric'}).toUpperCase();
  updateFoot();

  if(name==='today') wireToday();
  if(name==='setup') wireSetup();
  if(changedView) window.scrollTo({top:0,behavior:'instant'});
}

window.addEventListener('hashchange',render);
// The rest timer widget lives outside #view and survives route changes, so
// its controls are wired once here rather than inside wireToday().
document.getElementById('rtStop').onclick=stopRestTimer;
document.getElementById('rtAdd').onclick=()=>{
  if(!restTimer.total) return;
  restTimer.total+=30; restTimer.remaining+=30; renderRestTimer();
};
load();
render();

/* Identity and first sync happen after paint so the app never waits on the network. */
Sync.onChange(()=>{
  updateFoot();
  /* Setup shows live sync state, so redraw it when that changes — unless
     the person is mid-edit in a field. */
  if(route()==='setup'){
    const busy=document.activeElement && document.activeElement.tagName==='INPUT';
    if(!busy) render();
  }
});
fetchIdentity().then(id=>{ if(id){ identity=id; render(); } });
Sync.run(S).then(merged=>{ if(merged) adoptMerged(merged); else updateFoot(); });

function whoopRerenderIfShown(){
  if(route()==='today' || route()==='setup') render();
}
Whoop.today().then(whoopRerenderIfShown);

/* WHOOP just redirected back from its consent screen. The query string
   rides alongside the hash router rather than replacing it. */
(function(){
  const params=new URLSearchParams(location.search);
  const w=params.get('whoop');
  if(!w) return;
  const msgs={
    connected:'WHOOP connected.',
    denied:'WHOOP connection was not approved.',
    error:'WHOOP connection failed — try again from Setup.',
    expired:'That WHOOP connection link expired — try again from Setup.',
    tokenerror:'WHOOP did not accept the connection — try again from Setup.'
  };
  toast(msgs[w] || `WHOOP: ${w}`);
  history.replaceState(null,'',location.pathname+location.hash);
  if(w==='connected') Whoop.today(true).then(whoopRerenderIfShown);
})();

window.addEventListener('online', ()=>{ Sync.reset(); Sync.schedule(()=>S, adoptMerged, 400); });
document.addEventListener('visibilitychange', ()=>{
  if(document.visibilityState==='visible'){
    if(syncClock()) render();
    Sync.schedule(()=>S, adoptMerged, 600);
    Whoop.today().then(whoopRerenderIfShown);
  }
});
/* Catches the case where the app is left open and visible straight through
   midnight, so visibilitychange never fires. */
setInterval(()=>{ if(syncClock()) render(); }, 60_000);

if('serviceWorker' in navigator && location.protocol==='https:'){
  navigator.serviceWorker.register('sw.js').then(reg=>{
    const showBar=worker=>{
      const bar=document.getElementById('updatebar');
      bar.hidden=false;
      document.getElementById('updateBtn').onclick=()=>worker.postMessage('SKIP_WAITING');
    };
    // A worker already sitting in "waiting" from before this page load
    // (e.g. the update installed while the tab was in the background).
    if(reg.waiting) showBar(reg.waiting);
    reg.addEventListener('updatefound',()=>{
      const nw=reg.installing;
      if(!nw) return;
      nw.addEventListener('statechange',()=>{
        // navigator.serviceWorker.controller is only set once some worker
        // has ever controlled this page — its absence means this install
        // is the very first one, not an update, so there's nothing to
        // announce.
        if(nw.state==='installed' && navigator.serviceWorker.controller) showBar(nw);
      });
    });
  }).catch(()=>{});
  let reloading=false;
  navigator.serviceWorker.addEventListener('controllerchange',()=>{
    if(reloading) return;
    reloading=true;
    location.reload();
  });
}
