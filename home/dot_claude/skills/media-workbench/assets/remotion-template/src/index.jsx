import React from 'react';
import {AbsoluteFill, Audio, Composition, interpolate, registerRoot, spring, staticFile, useCurrentFrame, useVideoConfig} from 'remotion';

const ink = '#0c1116';
const paper = '#f3efe2';
const accent = '#adf0bc';
const clamp = {extrapolateLeft: 'clamp', extrapolateRight: 'clamp'};
const chapters = [
  {eyebrow: '01 / THINK', title: ['Curiosity,', 'in motion.'], caption: 'An idea becomes a question. A question becomes a world.', labels: ['RESEARCH', 'MODEL', 'EXPERIMENT'], number: '01'},
  {eyebrow: '02 / MAKE', title: ['Tools that', 'speak together.'], caption: 'Code. Shape. Animate. Edit. Keep the creative loop alive.', labels: ['CODE', '3D + MOTION', 'EDIT + SOUND'], number: '02'},
  {eyebrow: '03 / FINISH', title: ['From possibility', 'to something real.'], caption: 'A project you can open. A result you can see and hear.', labels: ['SAVE', 'RENDER', 'REOPEN'], number: '03'},
];

function Orbit({frame, section}) {
  const progress = interpolate(frame, [15, 150], [0, 1], clamp);
  const rotate = frame * .11 + section * 24;
  return <svg width="840" height="760" viewBox="0 0 840 760" style={{position: 'absolute', right: 5, top: 120}}>
    <defs><radialGradient id="halo"><stop offset="0" stopColor={accent} stopOpacity=".17"/><stop offset="1" stopColor={accent} stopOpacity="0"/></radialGradient></defs>
    <circle cx="420" cy="375" r="360" fill="url(#halo)"/>
    {[140, 220, 300].map((r, i) => <g key={r} transform={`rotate(${rotate * (i % 2 ? -1 : 1)},420,375)`}>
      <ellipse cx="420" cy="375" rx={r} ry={r * .62} fill="none" stroke={i === 1 ? '#93b8a4' : '#3c534d'} strokeWidth="1.5" transform={`rotate(${i * 55},420,375)`}/>
      <circle cx={420+r*Math.cos(i*1.25)} cy={375+r*.62*Math.sin(i*1.25)} r={i===1 ? 8 : 5} fill={accent}/>
    </g>)}
    <g transform={`translate(420 375) scale(${.7+progress*.3}) rotate(${rotate/3})`}>
      <path d="M0 -85 L73 -42 L73 42 L0 85 L-73 42 L-73 -42Z" fill={ink} stroke={accent} strokeWidth="2"/>
      <path d="M0 -85V85M-73 -42L73 42M73 -42L-73 42" stroke={accent} strokeOpacity=".65" strokeWidth="1"/>
      <circle r="9" fill={paper}/>
    </g>
    {[0,1,2].map((i) => {
      const y = 140 + i*230;
      const x = [260,590,260][i];
      const p = interpolate(frame, [30+i*18, 60+i*18], [0,1], clamp);
      return <g key={i} opacity={p} transform={`translate(${x} ${y + (1-p)*14})`}>
        <rect x="-88" y="-23" width="176" height="46" rx="23" fill={ink} stroke="#667d6e"/>
        <circle cx="-65" cy="0" r="3" fill={accent}/>
        <text x="4" y="5" textAnchor="middle" fill={paper} fontSize="13" fontFamily="Arial, sans-serif" letterSpacing="1.8">{chapters[section].labels[i]}</text>
      </g>;
    })}
  </svg>;
}

function Film() {
  const frame = useCurrentFrame();
  const {fps, durationInFrames} = useVideoConfig();
  const section = Math.min(2, Math.floor(frame/240));
  const local = frame % 240;
  const content = chapters[section];
  const enter = spring({frame: local, fps, config: {damping: 28, stiffness: 80}});
  const exit = interpolate(local, [222,239], [1,0], clamp);
  const ending = interpolate(frame, [690,719], [1,0], clamp);
  return <AbsoluteFill style={{background: ink, color: paper, fontFamily: 'Arial, Helvetica, sans-serif'}}>
    <Audio src={staticFile('score.wav')}/>
    <AbsoluteFill style={{backgroundImage: 'radial-gradient(#a4c2ae26 .8px, transparent .8px)', backgroundSize: '26px 26px', opacity: .25}}/>
    <div style={{position:'absolute', left:96, right:96, top:62, display:'flex', justifyContent:'space-between', fontSize:18, letterSpacing:3}}><span>CADE / CREATIVE SYSTEMS</span><span style={{color:accent}}>A WORKING ENVIRONMENT</span></div>
    <div style={{position:'absolute',top:110,left:96,right:96,height:1,background:'#34443b'}}/>
    <AbsoluteFill style={{opacity:exit*ending}}>
      <Orbit frame={local} section={section}/>
      <div style={{position:'absolute',left:96,top:228,transform:`translateY(${(1-enter)*42}px)`,opacity:enter}}>
        <div style={{color:accent,fontSize:21,letterSpacing:4,marginBottom:52}}>{content.eyebrow}</div>
        <div style={{fontSize:88,fontWeight:500,letterSpacing:-4,lineHeight:1.04}}>{content.title.map((line)=><div key={line}>{line}</div>)}</div>
        <div style={{fontSize:26,color:'#b2beb4',lineHeight:1.5,maxWidth:670,marginTop:38}}>{content.caption}</div>
      </div>
      <div style={{position:'absolute',left:100,bottom:156,display:'flex',alignItems:'center',gap:18,color:accent,fontSize:17,letterSpacing:2}}><span style={{width:40,height:1,background:accent}}/>LOCAL TOOLS · OPEN POSSIBILITIES</div>
    </AbsoluteFill>
    <div style={{position:'absolute',bottom:70,left:96,right:96,height:2,background:'#34443b'}}><div style={{height:2,width:`${frame/(durationInFrames-1)*100}%`,background:accent}}/></div>
    <div style={{position:'absolute',bottom:32,left:96,right:96,display:'flex',justifyContent:'space-between',fontSize:14,letterSpacing:2,color:'#899a8f'}}><span>THINK / MAKE / FINISH</span><span>{String(Math.floor(frame/fps)).padStart(2,'0')} / 24</span></div>
  </AbsoluteFill>;
}

registerRoot(() => <Composition id="CreativeSystem" component={Film} durationInFrames={720} fps={30} width={1920} height={1080}/>);
