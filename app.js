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
            {n:'Core finisher',p:'ab wheel or plank 3×45s · Pallof press 3×10 / side'},
            {n:'Post-match shake',p:'30g whey + 300ml milk + banana'}]},
  2:{label:'TU',color:'#E23B3B',title:'Upper · Strength',tag:'Rest 2–3 min',restSec:150,
     note:'The heavy day. Add weight or a rep whenever you hit the top of the range.',
     items:[{n:'Band pull-aparts + arm circles',p:'warm-up 2×15'},
            {n:'Weighted pull-ups',p:'4 × 5–8 — add weight at 8',id:'wpullup'},
            {n:'Incline DB press',p:'4 × 8–10',id:'incline'},
            {n:'Barbell or DB row',p:'4 × 8–10',id:'row'},
            {n:'Overhead press',p:'3 × 8–10',id:'ohp'},
            {n:'Dips',p:'3 × to 2 reps shy of failure',id:'dips'},
            // Shares the 'lat' id with Friday on purpose: one combined
            // progression history rather than two half-pictures.
            {n:'Lateral raises',p:'3 × 12–15 — strict, no swing',id:'lat'}]},
  3:{label:'WE',color:'#E23B3B',title:'Lower · Strength',tag:'Rest 2–3 min',restSec:150,
     note:'If Monday tennis left you wrecked, swap this with Tuesday.',
     items:[{n:'Leg swings · hip circles · 90/90',p:'warm-up 5 min'},
            {n:'Squat or trap bar deadlift',p:'4 × 5–8',id:'squat'},
            {n:'Romanian deadlift',p:'3 × 8–10',id:'rdl'},
            // The RDL is pure hip extension. The short head of the biceps
            // femoris only crosses the knee, so it barely works in any
            // hinge — this is the movement that actually trains it.
            {n:'Leg curl or Nordic',p:'3 × 8–12',id:'legcurl'},
            {n:'Bulgarian split squat',p:'3 × 10 / leg',id:'bss'},
            {n:'Calf raises',p:'3 × 15',id:'calf'},
            {n:'Hanging leg raises',p:'3 × 12 — add a dumbbell between the feet when 12 is easy',id:'hlr'}]},
  4:{label:'TH',color:'#D9A13B',title:'Easy Cardio',tag:'Zone 2 only',
     note:'Conversational pace. If WHOOP recovery is red, take the full rest instead — this is the first thing to drop.',
     items:[{n:'Zone 2',p:'20–35 min easy jog, bike or brisk hike'},
            {n:'Daily mobility',p:'see below'}]},
  5:{label:'FR',color:'#E23B3B',title:'Upper · Volume',tag:'Rest 60–90s',restSec:75,
     note:'Chase the pump here. Side and rear delts are what make the suit fit — and they only get trained if you actually load them.',
     items:[{n:'Band pull-aparts',p:'warm-up 2×15'},
            {n:'Pull-ups',p:'4 × max reps',id:'pullup'},
            {n:'Flat DB press',p:'4 × 10–12',id:'flat'},
            {n:'Cable or band row',p:'3 × 12',id:'crow'},
            {n:'Lateral raises',p:'4 × 15',id:'lat'},
            // Promoted from a warm-up to real loaded sets — rear delts had
            // no working volume anywhere in the week.
            {n:'Face pulls',p:'3 × 15 — load it, pause at the face',id:'facepull'},
            {n:'Curls + triceps',p:'3 × 12 each',id:'arms'}]},
  6:{label:'SA',color:'#E23B3B',title:'Lower + Pyramid',tag:'Treat it as a session',
     note:'The pyramid is a full session element, not an add-on. Alternate the two ways of progressing it: one week add a round, the next keep the same rounds and wear the vest.',
     items:[{n:'Front or goblet squat',p:'4 × 8',id:'fsquat'},
            {n:'Box jumps',p:'4 × 6 explosive, full rest',id:'boxjump'},
            {n:'Calf raises',p:'3 × 12–15 — pause at the top',id:'calf'},
            // Loaded flexion, so abs get progressive overload like anything
            // else. The pyramid's sit-ups are endurance work, not growth.
            {n:'Cable crunch or weighted sit-up',p:'3 × 10–15 — add load, not reps',id:'crunch'},
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
// pyramidCap starts at 4 (150 reps), not 6 (315). A fresh install opening on
// a session you cannot finish teaches you to ignore the number.
const DEFAULTS = {startDate:todayISO, weights:[], logs:{}, lifts:{}, whoop:{},
  pyramidCap:4, vestKg:null, vestPhase:0, calAdjust:0, updatedAt:0};
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
      if(!S.whoop || typeof S.whoop !== 'object') S.whoop = {};
    }
  }catch(e){
    toast('Saved data could not be read. Starting fresh.');
    S = structuredClone(DEFAULTS);
  }
  if(!S.weights.length) S.weights = [{d:todayISO, kg:79}];
}
/* Write to disk and queue a push, WITHOUT claiming the record changed.
   Used for data the app derives rather than the person entering it (WHOOP
   readings): bumping updatedAt for those would let an idle phone waking in
   a pocket win the "newer write wins" merge for today and overwrite ticks
   just made on another device. */
function persistLocal(){
  try{ localStorage.setItem(STORE_KEY, JSON.stringify(S)); }
  catch(e){ /* quota — the in-memory copy still works for this session */ }
  Sync.schedule(()=>S, adoptMerged);
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
/* Key order must not decide whether two records count as equal. This used
   to be a plain JSON.stringify against a hand-listed field order that
   happened to match mergeState's output — so adding a field to either side
   made every merge look like a change and forced a redraw each sync. */
function stableStringify(v){
  if(v===null||typeof v!=='object') return JSON.stringify(v);
  if(Array.isArray(v)) return '['+v.map(stableStringify).join(',')+']';
  return '{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+stableStringify(v[k])).join(',')+'}';
}
function adoptMerged(merged){
  if(stableStringify(merged)===stableStringify(stripLocal(S))){ updateFoot(); return; }
  const busy = document.activeElement && document.activeElement.tagName==='INPUT';
  if(busy){ deferredMerge = merged; updateFoot(); return; }
  S = Object.assign(structuredClone(DEFAULTS), merged);
  try{ localStorage.setItem(STORE_KEY, JSON.stringify(S)); }catch(e){}
  render();
}
function stripLocal(o){
  const {startDate,weights,logs,lifts,whoop,pyramidCap,vestKg,vestPhase,calAdjust,updatedAt}=o;
  return {updatedAt:updatedAt||0,startDate,pyramidCap,
    vestKg:vestKg??null,vestPhase:vestPhase||0,calAdjust,weights,logs,lifts,whoop:whoop||{}};
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
/* The rate that drives the calorie advice below. Deliberately a rolling
   window, not the whole history: comparing the first weigh-ins ever against
   the most recent ones measures a chord across the entire log, so months in
   it reports a lifetime average and keeps saying "on target" during a
   multi-week stall — exactly when it should be saying to eat more.
   Least-squares over the window rather than first-vs-last, so one heavy
   water-weight morning at either edge doesn't swing the whole verdict. */
const TREND_DAYS = 28;
const TREND_MIN_POINTS = 4;
const TREND_MIN_SPAN = 10;
function trend(){
  const w=sortW();
  if(w.length<TREND_MIN_POINTS) return null;
  const cutoff=new Date(w.at(-1).d);
  cutoff.setDate(cutoff.getDate()-TREND_DAYS);
  const win=w.filter(x=>new Date(x.d)>=cutoff);
  if(win.length<TREND_MIN_POINTS) return null;

  const t0=new Date(win[0].d).getTime();
  const xs=win.map(x=>(new Date(x.d)-t0)/864e5), ys=win.map(x=>x.kg);
  const span=xs.at(-1);
  if(span<TREND_MIN_SPAN) return null;

  const mx=avg(xs), my=avg(ys);
  let num=0, den=0;
  for(let i=0;i<xs.length;i++){ num+=(xs[i]-mx)*(ys[i]-my); den+=(xs[i]-mx)**2; }
  if(!den) return null;
  return {rate:(num/den)*30, days:span, points:win.length};
}
const CAL_STEP = 200;
function verdict(){
  const t=trend();
  if(!t) return {cls:'',html:`Log ${TREND_MIN_POINTS}+ weigh-ins over a couple of weeks to see your rate.`};
  const r=t.rate, cls = r<0.35?'slow':r>1.0?'fast':'ok';
  const tail = cls==='slow' ? `Below target — add ${CAL_STEP} kcal (more milk, bigger rice portion).`
             : cls==='fast' ? 'Faster than a lean bulk needs. Hold calories steady.'
             : 'On target for a lean bulk.';
  return {cls, html:`<b>${r>0?'+':''}${r.toFixed(2)} kg / month</b> over the last ${Math.round(t.days)} days. ${tail}`};
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
/* Work done in one session. Bodyweight sets carry no load, so kg-volume
   would read 0 and look like nothing happened — report total reps for
   those instead and let the caller label it. */
function volumeOf(entry){
  const sets=setsOf(entry);
  const reps=sets.reduce((n,s)=>n+(s.reps||0),0);
  const weighted=sets.filter(s=>s.kg!=null&&s.kg>0);
  if(!weighted.length) return {reps, kg:null};
  return {reps, kg:Math.round(weighted.reduce((n,s)=>n+s.kg*(s.reps||0),0))};
}
const fmtVolume = v => v.kg!=null ? `${v.kg} kg vol` : `${v.reps} reps`;
/* Epley. Only meaningful for loaded sets, and it drifts badly at very high
   reps, so cap where the formula still says something useful. */
function e1rm(set){
  if(!set || set.kg==null || !set.kg || !set.reps || set.reps>15) return null;
  return set.kg*(1+set.reps/30);
}
const bestE1rm = entry => e1rm(bestSet(entry));

/* "You logged it, but it hasn't moved." Only fires with enough recent
   entries to be a real plateau rather than a two-week gap. */
const STALL_DAYS = 28;
const STALL_MIN_SESSIONS = 3;
function stallInfo(history){
  const withE=history.map(e=>({d:e.d, v:bestE1rm(e)})).filter(x=>x.v!=null);
  if(withE.length<STALL_MIN_SESSIONS) return null;
  const cutoff=new Date(withE.at(-1).d);
  cutoff.setDate(cutoff.getDate()-STALL_DAYS);
  const recent=withE.filter(x=>new Date(x.d)>=cutoff);
  if(recent.length<STALL_MIN_SESSIONS) return null;
  const peak=Math.max(...withE.map(x=>x.v));
  // First time the peak was reached, not the last. Someone grinding the
  // same 100x5 every week has the peak value on every entry including
  // today's — taking the latest would read that as a fresh PR and never
  // flag anything. Matching an old best is not progress.
  const peakAt=withE.find(x=>x.v===peak);
  // Peak first set inside the window means it's genuinely still moving.
  if(new Date(peakAt.d)>=cutoff) return null;
  const weeks=Math.round((new Date(withE.at(-1).d)-new Date(peakAt.d))/6048e5);
  return {weeks:Math.max(weeks,1), sessions:recent.length};
}

/* The pyramid, precisely. Round N is N pull-ups, 2N dips, 3N push-ups,
   4N sit-ups, 5N squats — the 1:2:3:4:5 ratio roughly matching how hard
   each movement is. Climbing "to cap C" means doing rounds 1 through C, so
   each movement's total is its ratio times the Cth triangular number. That
   makes total work grow with the SQUARE of the cap: 6 to 10 is not four
   more rounds, it is 2.6x the reps. Hence alternating load instead. */
const PYRAMID_RATIO = [
  {n:'pull-ups',k:1},{n:'dips',k:2},{n:'push-ups',k:3},{n:'sit-ups',k:4},{n:'squats',k:5}
];
function pyramidTotals(cap){
  const tri = cap*(cap+1)/2;
  const parts = PYRAMID_RATIO.map(r=>({n:r.n, reps:r.k*tri}));
  return {parts, total: parts.reduce((n,p)=>n+p.reps,0)};
}

/* Suggested vest load. Scales with bodyweight so it tracks the bulk without
   being touched, and mildly with the cap, since a higher cap is evidence of
   capacity. Deliberately conservative — the usual guide for loaded
   calisthenic volume is 5-10% of bodyweight, and the rep count is already
   climbing quadratically underneath it. */
const VEST_PCT_MIN = 0.05, VEST_PCT_MAX = 0.08;
function suggestedVestKg(){
  const bw = latestAvg();
  if(bw==null) return null;
  const cap = Math.min(10, Math.max(3, S.pyramidCap));
  const pct = VEST_PCT_MIN + ((cap-3)/7)*(VEST_PCT_MAX-VEST_PCT_MIN);
  return Math.round(bw*pct*2)/2;          // nearest 0.5 kg
}
const vestKg = () => S.vestKg!=null ? S.vestKg : suggestedVestKg();
/* Alternation does NOT start from week one. While the cap is still low,
   adding a round is the cheap progression — cap 4 to 5 is 150 reps to 225 —
   so just climb. The vest earns its place once a round starts costing 100+
   reps, which is around cap 6. Below that, alternating would be adding load
   to someone who hasn't finished learning the movement volume yet.
   vestPhase only flips which parity carries the vest, for when the real
   schedule drifts out of step with the counter. */
const VEST_FROM_CAP = 6;
const isVestWeek = () =>
  S.pyramidCap >= VEST_FROM_CAP && ((weeksIn() + (S.vestPhase||0)) % 2) === 1;

function itemsFor(dow){
  return SCHEDULE[dow].items.map(it=>{
    if(it.n!=='PYRAMID') return it;
    const on=isVestWeek(), v=vestKg();
    return {...it,
      n:`Holland pyramid — rounds 1–${S.pyramidCap}${on&&v!=null?` · vest ${v.toFixed(1)} kg`:''}`,
      p:'round N = N pull-ups · 2N dips · 3N push-ups · 4N sit-ups · 5N squats'};
  });
}
function refText(id,activeDate){
  const h=S.lifts[id]||[];
  const mine=h.find(x=>x.d===activeDate);
  const last=[...h].filter(x=>x.d!==activeDate).sort((a,b)=>a.d<b.d?-1:1).pop();
  const fmtAll=e=>setsOf(e).map(fmtSet).join(' · ');
  // Once there's more than one set logged, the individual sets are already
  // visible in the inputs right above — the useful summary is the totals.
  const totals=e=>{
    const v=volumeOf(e), est=bestE1rm(e);
    return setsOf(e).length>1 ? ` · ${fmtVolume(v)}${est?` · e1RM ${est.toFixed(0)}`:''}` : '';
  };
  if(!last) return mine?`logged ${fmtAll(mine)}${totals(mine)}`:'first entry — this becomes your benchmark';
  let s=`last ${fmtAll(last)}${totals(last)} · ${last.d.slice(5)}`;
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
/* Tiny inline trend line for a single lift's e1RM series. Flat-line safe
   (a lifter who hasn't changed load has hi===lo, which would divide by
   zero and blank the chart). */
function miniSpark(values){
  if(values.length<2) return '';
  const lo=Math.min(...values), hi=Math.max(...values), span=(hi-lo)||1;
  const W=64,H=18;
  const pts=values.map((v,i)=>[(i/(values.length-1))*W, H-((v-lo)/span)*H]);
  const line=pts.map((p,i)=>`${i?'L':'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ');
  const rising=values.at(-1)>=values[0];
  return `<svg class="minispark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none" aria-hidden="true">
    <path d="${line}" fill="none" stroke="${rising?'#4FB477':'#868FA6'}" stroke-width="1.3"
      vector-effect="non-scaling-stroke" stroke-linejoin="round" stroke-linecap="round"/>
    <circle cx="${pts.at(-1)[0].toFixed(1)}" cy="${pts.at(-1)[1].toFixed(1)}" r="1.6" fill="#EDE7DB"/></svg>`;
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
/* Shared by the consistency chart and the weekly review so the two can
   never disagree about what counts. Thu (cardio) and Sun (rest) only have
   2 items, so a flat >=3 would make them impossible to ever complete. */
const sessionNeed = dow => Math.min(3, SCHEDULE[dow].items.length);
function didSession(date){
  const l=S.logs[iso(date)];
  return !!(l && l.done && l.done.length >= sessionNeed(date.getDay()));
}
function sessionsBetween(start, end){
  let n=0;
  for(let d=new Date(start); d<=end; d.setDate(d.getDate()+1)) if(didSession(d)) n++;
  return n;
}
/* Monday-start, matching ORDER and how the plan itself is written. */
function weekStart(date){
  const d=new Date(date);
  d.setHours(0,0,0,0);
  d.setDate(d.getDate()-((d.getDay()+6)%7));
  return d;
}
const GREEN_WEEK = 4;   // the "four green weeks in a row" the Progress copy calls the real win
/* Earliest day this log knows about. Weigh-ins alone are the wrong marker:
   a device restored from a partial backup, or someone who logged sessions
   for weeks before their first weigh-in, would otherwise have the streak
   cut off at whatever date that first weigh-in happens to carry. */
function logStart(){
  const dates=Object.keys(S.logs||{});
  if(S.weights.length) dates.push(sortW()[0].d);
  if(S.startDate) dates.push(S.startDate);
  return dates.length ? dates.sort()[0] : null;
}
function greenStreak(){
  const from=logStart();
  if(!from) return 0;
  let streak=0;
  // Start from last week: the current one is still in progress and would
  // read as a broken streak every Monday morning.
  for(let k=1;k<=52;k++){
    const start=weekStart(new Date()); start.setDate(start.getDate()-7*k);
    const end=new Date(start); end.setDate(end.getDate()+6);
    // Weeks from before this log existed aren't failures, just absent.
    if(end < new Date(from)) break;
    if(sessionsBetween(start,end) >= GREEN_WEEK) streak++; else break;
  }
  return streak;
}

function weeklyReview(){
  const thisStart=weekStart(new Date());
  const thisEnd=new Date(thisStart); thisEnd.setDate(thisEnd.getDate()+6);
  const prevStart=new Date(thisStart); prevStart.setDate(prevStart.getDate()-7);
  const prevEnd=new Date(thisStart); prevEnd.setDate(prevEnd.getDate()-1);

  const done=sessionsBetween(thisStart, new Date());
  // Target excludes the full-rest day — six trainable days a week.
  const target=ORDER.filter(d=>d!==0).length;

  const inRange=(a,b)=>sortW().filter(x=>{ const d=new Date(x.d); return d>=a&&d<=b; }).map(x=>x.kg);
  const thisW=inRange(thisStart,thisEnd), prevW=inRange(prevStart,prevEnd);
  const delta=(thisW.length&&prevW.length) ? avg(thisW)-avg(prevW) : null;

  // Seeding reduce() with null would hand beats() a null on the first
  // iteration; reducing an empty array without a seed throws instead. Both
  // cases are reachable from real data, so handle emptiness explicitly.
  const bestAcross=entries=>{
    const s=entries.map(bestSet).filter(Boolean);
    return s.length ? s.reduce((a,b)=>beats(b,a)?b:a) : null;
  };
  const improved=[];
  Object.keys(S.lifts||{}).forEach(id=>{
    const h=[...(S.lifts[id]||[])].sort((a,b)=>a.d<b.d?-1:1);
    const cur=h.filter(e=>{ const d=new Date(e.d); return d>=thisStart&&d<=thisEnd; });
    if(!cur.length) return;
    const before=h.filter(e=>new Date(e.d)<thisStart);
    if(!before.length) return;
    const bestBefore=bestAcross(before), bestNow=bestAcross(cur);
    if(bestBefore&&bestNow&&beats(bestNow,bestBefore)) improved.push(id);
  });

  const streak=greenStreak();
  return {done, target, delta, improved, streak,
    label:`${thisStart.toLocaleDateString('en-GB',{day:'numeric',month:'short'})} – ${thisEnd.toLocaleDateString('en-GB',{day:'numeric',month:'short'})}`};
}

function adherence(){
  const bars=[];
  for(let k=7;k>=0;k--){
    const end=new Date(); end.setDate(end.getDate()-k*7);
    const start=new Date(end); start.setDate(start.getDate()-6);
    bars.push(sessionsBetween(start,end));
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
function whoopBadge(offerTick){
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

  // Ignore very short activities — WHOOP records plenty of incidental ones
  // and "you trained today" should mean an actual session.
  const workouts = (w.workouts || []).filter(x => x.minutes == null || x.minutes >= 10);
  const tItems = itemsFor(todayDow);
  const complete = dayLog(todayISO).done.length >= tItems.length;
  const detected = workouts.length ? `
    <div class="wkdetect">
      <div>WHOOP recorded ${workouts.map(x =>
        `${escapeHtml(x.sport || 'a workout')}${x.minutes ? ` · ${x.minutes} min` : ''}${x.strain != null ? ` · ${x.strain.toFixed(1)} strain` : ''}`
      ).join(', ')} today.</div>
      ${offerTick && !complete ? `<button id="tickSession">Tick this session</button>` : ''}
    </div>` : '';

  return `<section class="panel">
    <div class="phead"><div class="ptitle">Recovery</div>
      <div class="ptag whoop-badge ${cls}">${recLabel}</div></div>
    <div class="whoop-row">
      <div><b>${strain}</b><span>strain</span></div>
      <div><b>${sleepPct}</b><span>sleep</span></div>
      <div><b>${hrv}</b><span>hrv ms</span></div>
      <div><b>${rhr}</b><span>rhr</span></div>
    </div>
    ${detected}
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

function pyramidPanel(){
  const cap=S.pyramidCap, t=pyramidTotals(cap);
  const climbing = cap < VEST_FROM_CAP;
  const on=isVestWeek(), v=vestKg();
  const kg = v==null ? '–' : v.toFixed(1);
  const next = pyramidTotals(Math.min(10,cap+1));

  return `
  <div class="wrow"><button data-cap="-1">– round</button>
    <button data-cap="1">+ round</button>
    <span class="ptag">cap ${cap}${climbing?` · vest at ${VEST_FROM_CAP}`:' · build to 10'}</span></div>
  <div class="pnote">Rounds 1–${cap} adds up to ${t.parts.map(p=>`<b>${p.reps}</b> ${p.n}`).join(' · ')}
    — <b>${t.total}</b> reps.${cap<10?` One more round makes it <b>${next.total}</b>.`:''}</div>
  <div class="wrow vestrow">
    <span class="ptag">${climbing?'Climbing' : on?'Vest week':'Bodyweight week'}</span>
    ${climbing?`<span class="ptag">vest starts at cap ${VEST_FROM_CAP}</span>`
      :on?`<button data-vest="-0.5">–</button><b class="vestkg">${kg} kg</b><button data-vest="0.5">+</button>
        ${S.vestKg!=null?`<button data-vest="auto">auto</button>`:''}`
      :`<span class="ptag">next week: ${kg} kg</span>`}
    ${climbing?'':`<button id="vestSwap">swap</button>`}
  </div>
  <div class="pnote">${climbing
    ? `Set the cap to the round you can actually finish — that is what it is for, not a target you are failing. Add a round once ${cap} goes through cleanly. The vest stays off until cap ${VEST_FROM_CAP}, because until then adding a round is the cheaper way to progress.`
    : on
    ? `Same ${cap} rounds as last week, wearing the vest — that is this week's progression. Add the round next week instead.`
    : `Add a round if last week's ${cap} moved well. Next week is the same cap with the vest on.`}
    ${climbing?'':(S.vestKg!=null?' Weight set by hand — <b>auto</b> returns it to tracking your bodyweight.'
      :' Suggested weight tracks your bodyweight and cap; adjust it and it sticks.')
      + ' Use <b>swap</b> if the vest lands on the wrong week.'}</div>`;
}

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
  // Only offer to tick from a detected workout when the ticks would land on
  // today — not while previewing another weekday or back-filling a past one.
  return spine + backfill + whoopBadge(canEdit && !editingDate) + `
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
    ${viewing===6?pyramidPanel():''}
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
    ${v.cls==='slow'?`<div class="wrow suggest">
      <span class="ptag">Trend is below target</span>
      <button class="primary" id="applyCal">Apply + ${CAL_STEP} kcal</button>
    </div>`:''}
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
  const r=weeklyReview();

  return `
  <section class="panel">
    <div class="phead"><div class="ptitle">This week</div><div class="ptag">${r.label}</div></div>
    <div class="macros">
      <div class="macro"><b>${r.done}<span class="of">/${r.target}</span></b><span>sessions</span></div>
      <div class="macro"><b>${r.delta==null?'–':(r.delta>0?'+':'')+r.delta.toFixed(1)}</b><span>kg vs last wk</span></div>
      <div class="macro"><b>${r.improved.length}</b><span>lifts up</span></div>
      <div class="macro"><b>${r.streak}</b><span>green weeks</span></div>
    </div>
    ${r.improved.length?`<div class="pnote">Beaten this week: <b>${r.improved.map(id=>named[id]||id).join(', ')}</b>.</div>`:''}
    <div class="pnote">${r.streak>=GREEN_WEEK
      ? `<b>${r.streak} weeks running</b> at ${GREEN_WEEK}+ sessions. This is the part that actually builds the body — keep it boring.`
      : r.streak>0
      ? `${r.streak} week${r.streak===1?'':'s'} running at ${GREEN_WEEK}+ sessions. ${GREEN_WEEK-r.streak} more for a full green month.`
      : `A week counts as green at ${GREEN_WEEK}+ sessions. The streak starts with one.`}</div>
  </section>

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
      const vol=volumeOf(lastDay.entry), est=bestE1rm(lastDay.entry);
      const series=days.map(x=>bestE1rm(x.entry)).filter(x=>x!=null);
      const stall=stallInfo(h);
      return `<div class="hist"><div class="hist-n">${named[id]||id}
          ${series.length>1?miniSpark(series):''}
          ${stall?`<div class="stall">no PR in ${stall.weeks} week${stall.weeks===1?'':'s'} · ${stall.sessions} sessions — change a variable</div>`:''}
        </div>
        <div class="hist-v"><b>${fmtAll(lastDay.entry)}</b> ${isBest?'<span class="up">▲ best</span>':''}<br>
        ${fmtVolume(vol)}${est?` · e1RM ${est.toFixed(0)}`:''}<br>
        best ${fmtSet(best.best)} · ${h.length} entr${h.length===1?'y':'ies'}</div></div>`}).join('')
      :`<div class="empty">Log a set on the Today page and your progression appears here.</div>`}
    <div class="pnote">e1RM is an Epley estimate from your best set — useful for comparing a heavy triple against a lighter set of ten, not a number to go and test.</div>
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
    <div class="pnote">JSON is the one to keep for restoring. CSV is for poking at the numbers in a spreadsheet — it can't be imported back.</div>
    <div class="wrow"><button id="csvW">Weigh-ins CSV</button>
      <button id="csvL">Lifts CSV</button></div>
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Start date</div><div class="ptag">Week counter</div></div>
    <div class="pnote">Currently week ${weeksIn()+1}. Set this to your real first training day — the add-ins unlock at week 12.</div>
    <div class="wrow"><input type="date" id="sd" value="${S.startDate}"><button id="sdSave">Save</button></div>
  </section>

  <section class="panel">
    <div class="phead"><div class="ptitle">Install</div><div class="ptag">Home screen</div></div>
    <div class="pnote">iOS: Share → Add to Home Screen. Android: menu → Install app. It then opens fullscreen and works offline in the gym.</div>
    <div class="pnote">Running <b>${cacheVersion ? cacheVersion.toUpperCase() : 'an unknown version'}</b>${pendingVersion && pendingVersion!==cacheVersion ? `, with <b>${pendingVersion.toUpperCase()}</b> installed and waiting to take over` : ''}. If an update refuses to take — the banner keeps coming back, or a change you know shipped isn't here — this throws away the offline cache and starts clean. <b>Your log is not touched</b>, and it re-downloads on the next load.</div>
    <div class="wrow"><button id="forceUpdate">Force update</button>
      <button id="swDiag">Worker details</button></div>
    <pre class="diag" id="swDiagOut" hidden></pre>
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
  document.querySelectorAll('[data-vest]').forEach(b=>b.onclick=()=>{
    if(b.dataset.vest==='auto'){ S.vestKg=null; }
    else {
      // Nudging from the suggestion pins it: once touched, it stops moving
      // on its own until "auto" hands it back.
      const base=vestKg()||0;
      S.vestKg=Math.max(0, Math.round((base + parseFloat(b.dataset.vest))*2)/2);
    }
    save(); render();
  });
  const vsw=document.getElementById('vestSwap');
  if(vsw) vsw.onclick=()=>{ S.vestPhase=((S.vestPhase||0)+1)%2; save(); render(); };
  document.querySelectorAll('[data-cal]').forEach(b=>b.onclick=()=>{
    S.calAdjust=(S.calAdjust||0)+ +b.dataset.cal; save(); render();
  });
  const ac=document.getElementById('applyCal');
  if(ac) ac.onclick=()=>{
    S.calAdjust=(S.calAdjust||0)+CAL_STEP; save(); render();
    toast(`Target raised by ${CAL_STEP} kcal. Give it two weeks.`);
  };
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
  const ts=document.getElementById('tickSession');
  if(ts) ts.onclick=()=>{
    // Explicit tap rather than auto-ticking on detection: WHOOP knows you
    // trained, it doesn't know which items on the checklist you actually did.
    const l=dayLog(todayISO);
    l.done=itemsFor(todayDow).map((_,i)=>i);
    save(); render(); toast('Session marked complete.');
  };

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
  /* The last-resort escape hatch. Getting a stuck service worker unstuck
     otherwise means Settings → Safari → Advanced → Website Data, which is
     both hard to find on a phone and wipes localStorage along with it.
     This tears down only the worker and its caches — the log lives in
     localStorage and is deliberately left alone. */
  const fu=document.getElementById('forceUpdate');
  if(fu) fu.onclick=async()=>{
    if(!confirm('Throw away the offline cache and reload?\n\nYour training log is not affected.')) return;
    fu.disabled=true;
    try{
      if('serviceWorker' in navigator){
        const regs=await navigator.serviceWorker.getRegistrations();
        await Promise.all(regs.map(r=>r.unregister().catch(()=>{})));
      }
      if('caches' in window){
        const keys=await caches.keys();
        await Promise.all(keys.map(k=>caches.delete(k).catch(()=>{})));
      }
    }catch(e){ /* fall through and reload anyway — a partial teardown still helps */ }
    // replace() rather than reload(): the query string defeats any HTTP
    // cache, and not leaving a history entry means Back can't return to a
    // page served by the worker that was just unregistered.
    location.replace(`${location.pathname}?fresh=${Date.now()}${location.hash}`);
  };

  /* Dumps the actual service worker state. Every round of "the update won't
     take" so far has been diagnosed by inference from screenshots; this
     makes the app say it outright. */
  const sd=document.getElementById('swDiag');
  if(sd) sd.onclick=async()=>{
    const out=document.getElementById('swDiagOut');
    out.hidden=false;
    out.textContent='reading…';
    const lines=[];
    try{
      lines.push(`page       ${location.href}`);
      lines.push(`sw support ${'serviceWorker' in navigator}`);
      if('serviceWorker' in navigator){
        const regs=await navigator.serviceWorker.getRegistrations();
        lines.push(`registrations ${regs.length}`);
        const ctrl=navigator.serviceWorker.controller;
        lines.push(`controller ${ctrl ? (await askVersion(ctrl)) || 'no answer' : 'none'}`);
        for(const [i,r] of regs.entries()){
          lines.push(`  [${i}] scope ${r.scope}`);
          for(const k of ['installing','waiting','active']){
            const w=r[k];
            lines.push(`      ${k.padEnd(10)} ${w ? `${w.state} · ${(await askVersion(w))||'no answer'}` : '—'}`);
          }
        }
      }
      if('caches' in window) lines.push(`caches     ${(await caches.keys()).join(', ')||'none'}`);
      lines.push(`online     ${navigator.onLine}`);
      lines.push(`sync       ${Sync.label()}`);
    }catch(e){ lines.push(`error      ${e && e.message}`); }
    out.textContent=lines.join('\n');
  };

  const ra=document.getElementById('reauth');
  // A plain reload can be answered straight from the service worker cache,
  // which is exactly the trap this button exists to get out of. The query
  // string guarantees a cache miss, so the request reaches the network and
  // Access can redirect to its login page.
  if(ra) ra.onclick=()=>{ location.href=`${location.pathname}?reauth=${Date.now()}${location.hash}`; };

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

  const download=(text,filename,type)=>{
    const blob=new Blob([text],{type});
    const a=document.createElement('a');
    a.href=URL.createObjectURL(blob);
    a.download=filename;
    a.click(); URL.revokeObjectURL(a.href);
  };
  document.getElementById('exp').onclick=()=>{
    download(JSON.stringify(S,null,2), `bnb-backup-${todayISO}.json`, 'application/json');
    toast('Backup file downloaded.');
  };
  // Quote anything a spreadsheet would otherwise split or mangle. Notes are
  // free text, so this is not theoretical.
  const csvCell=v=>{
    const s=v==null?'':String(v);
    return /[",\n]/.test(s) ? `"${s.replace(/"/g,'""')}"` : s;
  };
  const toCsv=rows=>rows.map(r=>r.map(csvCell).join(',')).join('\r\n');
  document.getElementById('csvW').onclick=()=>{
    const rows=[['date','kg'], ...sortW().map(x=>[x.d,x.kg])];
    download(toCsv(rows), `bnb-weighins-${todayISO}.csv`, 'text/csv');
    toast('Weigh-ins CSV downloaded.');
  };
  document.getElementById('csvL').onclick=()=>{
    const named={};
    ORDER.forEach(d=>itemsFor(d).forEach(it=>{ if(it.id) named[it.id]=it.n; }));
    const rows=[['date','lift_id','lift','set','kg','reps','e1rm']];
    Object.keys(S.lifts||{}).sort().forEach(id=>{
      [...(S.lifts[id]||[])].sort((a,b)=>a.d<b.d?-1:1).forEach(entry=>{
        setsOf(entry).forEach((s,i)=>{
          const est=e1rm(s);
          rows.push([entry.d, id, named[id]||id, i+1, s.kg==null?'':s.kg, s.reps, est?est.toFixed(1):'']);
        });
      });
    });
    download(toCsv(rows), `bnb-lifts-${todayISO}.csv`, 'text/csv');
    toast('Lifts CSV downloaded.');
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

/* Ask a worker directly which version it is. Reading Cache Storage instead
   was wrong in the one situation that matters: while an update is pending,
   both the running version's cache and the incoming one exist side by side,
   so the page reported the version that was about to arrive as though it
   were already serving — and had no way to tell a genuine pending update
   from a phantom one. Returns null for workers older than this change, or
   if the worker doesn't answer. */
function askVersion(worker){
  return new Promise(resolve=>{
    if(!worker) return resolve(null);
    try{
      const ch=new MessageChannel();
      const t=setTimeout(()=>resolve(null),1500);
      ch.port1.onmessage=ev=>{ clearTimeout(t); resolve(String(ev.data||'').replace(/^bnb-/,'')); };
      worker.postMessage('VERSION',[ch.port2]);
    }catch(e){ resolve(null); }
  });
}
let cacheVersion = '';
let pendingVersion = '';
async function readCacheVersion(){
  try{
    const sw = navigator.serviceWorker;
    const fromController = sw && sw.controller ? await askVersion(sw.controller) : null;
    let next = fromController;
    if(!next && 'caches' in window){
      // Fallback for a worker predating the VERSION message, or none at all.
      const verNum = k => parseInt(String(k).replace(/^bnb-v/,''),10) || 0;
      const mine=(await caches.keys()).filter(k=>k.startsWith('bnb-')).sort((a,b)=>verNum(a)-verNum(b));
      next = mine.length ? mine.at(-1).replace(/^bnb-/,'') : '';
    }
    if((next||'')===cacheVersion) return;
    cacheVersion = next||'';
    updateFoot();
    if(route()==='setup') render();
  }catch(e){ /* Cache Storage / messaging blocked — just omit the version */ }
}
function updateFoot(){
  const el=document.getElementById('foot');
  if(!el) return;
  el.textContent = `WEEK ${weeksIn()+1} · ${S.weights.length} WEIGH-INS · ${Sync.label()}`
    + (cacheVersion ? ` · ${cacheVersion.toUpperCase()}` : '');
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

/* WHOOP responses are transient — the client caches for ten minutes and
   forgets on reload, so nothing has ever been kept. Writing the daily
   numbers into state is what makes "did recovery actually track my
   training?" answerable later; that history only exists from the day it
   starts being recorded, which is the argument for doing it now. */
function recordWhoop(w){
  if(!w || !w.connected || !S.whoop) return;
  const scored = v => v && v.state === 'SCORED';
  const rec=w.recovery, str=w.strain, slp=w.sleep;
  if(!scored(rec) && !scored(str) && !scored(slp)) return;
  const entry={
    recovery: scored(rec) ? rec.score ?? null : null,
    strain:   scored(str) && str.value!=null ? Math.round(str.value*10)/10 : null,
    sleep:    scored(slp) ? slp.performance_pct ?? null : null,
    hrv:      scored(rec) && rec.hrv_ms!=null ? Math.round(rec.hrv_ms) : null,
    rhr:      scored(rec) ? rec.rhr ?? null : null
  };
  if(stableStringify(S.whoop[todayISO]||null)===stableStringify(entry)) return;
  S.whoop[todayISO]=entry;
  persistLocal();   // not save() — see persistLocal for why this must not bump updatedAt
}
function whoopRerenderIfShown(w){
  recordWhoop(w);
  if(route()==='today' || route()==='setup') render();
}
Whoop.today().then(whoopRerenderIfShown);

/* Tidy up the cache-busting param the re-auth button adds, so it doesn't
   linger in the URL or get bookmarked. */
(function(){
  if(new URLSearchParams(location.search).has('reauth'))
    history.replaceState(null,'',location.pathname+location.hash);
})();

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
    // An installed PWA is resumed for weeks without a real navigation, and
    // the browser's own update check is infrequent. Asking on resume is
    // what makes a deploy show up the next time the app is opened rather
    // than whenever the browser gets around to it.
    if(swRegistration) swRegistration.update().catch(()=>{});
    readCacheVersion();
  }
});
/* Catches the case where the app is left open and visible straight through
   midnight, so visibilitychange never fires. */
setInterval(()=>{ if(syncClock()) render(); }, 60_000);

let swRegistration = null;
readCacheVersion();
if('serviceWorker' in navigator && location.protocol==='https:'){
  let reloading=false;
  const reloadOnce=()=>{ if(reloading) return; reloading=true; location.reload(); };
  navigator.serviceWorker.addEventListener('controllerchange', reloadOnce);

  navigator.serviceWorker.register('sw.js').then(reg=>{
    swRegistration = reg;
    const DISMISS_KEY='bnb.updateDismissed.v1';
    const bar=()=>document.getElementById('updatebar');

    /* Only announce an update that is genuinely a different version.
       Previously any waiting worker raised the banner, so a worker that
       kept reinstalling — or one whose activation the browser never
       completed — produced a banner that came back after every reload with
       no way to get rid of it. Asking both workers their version settles
       whether there is actually anything to update to. */
    const maybeShowBar=async worker=>{
      if(!worker || !navigator.serviceWorker.controller) return;
      const [mine, theirs] = await Promise.all([
        askVersion(navigator.serviceWorker.controller), askVersion(worker)
      ]);
      /* Announce ONLY on positive confirmation that the waiting worker is a
         genuinely different version. Showing it whenever some worker was
         waiting is what produced a banner that came back after every reload
         — and when the version can't be established, the dismissal below
         has nothing to key against, so dismissing it did not stick either
         and it returned forever. Staying silent when unsure is the safer
         default now that Setup shows the running version outright and has a
         Force update button; a missed prompt is recoverable, an
         undismissable banner is not. */
      if(!(mine && theirs && mine !== theirs)) return;
      pendingVersion = theirs;
      // Respect a dismissal of this same pending version.
      try{ if(localStorage.getItem(DISMISS_KEY)===theirs) return; }catch(e){}

      const el=bar();
      const msg=document.getElementById('updateMsg');
      if(msg) msg.textContent = `Version ${theirs.toUpperCase()} is ready.`;
      el.hidden=false;
      document.getElementById('updateBtn').onclick=()=>{
        el.hidden=true;
        /* Ask the waiting worker to take over — then reload regardless.
           The handshake alone is not enough to rely on: a worker that was
           waiting when this banner appeared can activate by itself once the
           last other tab closes, and SKIP_WAITING sent to a worker that is
           already active does nothing at all. No controllerchange fires, so
           the page never reloads and the button looks broken. */
        try{ worker.postMessage('SKIP_WAITING'); }catch(e){}
        setTimeout(reloadOnce, 500);
      };
      document.getElementById('updateDismiss').onclick=()=>{
        el.hidden=true;
        // theirs is guaranteed non-empty by the check above, so this always
        // records something — the previous version could silently store
        // nothing and let the banner return on the next load.
        try{ localStorage.setItem(DISMISS_KEY, theirs); }catch(e){}
      };
    };

    if(reg.waiting) maybeShowBar(reg.waiting);
    reg.addEventListener('updatefound',()=>{
      const nw=reg.installing;
      if(!nw) return;
      nw.addEventListener('statechange',()=>{
        if(nw.state==='installed') maybeShowBar(nw);
      });
    });
  }).catch(()=>{});
}
