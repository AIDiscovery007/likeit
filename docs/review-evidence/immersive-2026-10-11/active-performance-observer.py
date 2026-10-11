import subprocess, time, json, pathlib
pid=54580
started=time.monotonic()
rows=[]
path=pathlib.Path('/tmp/likeit-immersive-review/final-d-active-performance.json')
while True:
    result=subprocess.run(['ps','-p',str(pid),'-o','pid=,time=,rss=,%cpu='],capture_output=True,text=True)
    elapsed=time.monotonic()-started
    row={'seconds':round(elapsed,3),'present':result.returncode==0}
    if result.returncode==0:
        ident,cpu,rss,instant=result.stdout.split()
        parts=cpu.split(':')
        row.update(cpuSeconds=sum(float(part)*60**index for index,part in enumerate(reversed(parts))),rssKiB=int(rss),reportedCPU=float(instant))
        observed=json.loads(subprocess.check_output(['/tmp/likeit-immersive-review/window-observer','1'],text=True))
        row['front']=[r['front'] for r in observed['transitions']]
        row['desktopPIDs']=observed['observedPIDs']
        row['visibleSamples']=observed['visibleSamples']
    rows.append(row)
    path.write_text(json.dumps({'pid':pid,'durationTarget':600,'samples':rows},indent=2)+'\n')
    if elapsed >= 600 or result.returncode != 0: break
    time.sleep(min(5,max(0,600-(time.monotonic()-started))))
print(json.dumps({'samples':len(rows),'duration':rows[-1]['seconds'],'present':rows[-1]['present']}))
