#!/usr/bin/env python3
"""Verify IEEE Number behavior using independent Node/Bun, Swift IR, Lean and TLC paths."""
import argparse
import concurrent.futures
import json
import os
from pathlib import Path
import shutil
import struct
import random
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--formal', type=Path, required=True)
parser.add_argument('--output', type=Path)
parser.add_argument('--skip-component', action='store_true', help='Reuse unchanged independent runtime-vector evidence')
parser.add_argument('--only', help='Comma-separated property names; skip component and finite checks')
args = parser.parse_args()
formal = args.formal.resolve()
root = Path(__file__).resolve().parents[1]
work = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix='formal-numbers-'))
if args.output: work.mkdir()
p = work / 'component'; p.mkdir()
records = []
selection = set(args.only.split(',')) if args.only else None
executed = []
tools = formal.parent / 'toolchain'
lean = (tools/'lean/bin/lean').resolve()
java = (tools/'java/Contents/Home/bin/java').resolve()
jar = (tools/'tla2tools.jar').resolve()

def run(command, expected=0, cwd=None, env=None, timeout=180):
    result = subprocess.run(list(map(str, command)), cwd=cwd or root, env=env, capture_output=True, text=True, timeout=timeout)
    if result.returncode != expected:
        raise AssertionError((command, result.returncode, result.stdout[-12000:], result.stderr[-12000:]))
    return result.stdout

if selection is None and not args.skip_component:
    ops=['numberAdd','numberSubtract','numberMultiply','numberDivide','numberRemainder','numberNegate','numberEqual','numberLessThan','numberLessEqual','numberSameValue','numberIsNaN','numberIsFinite','numberIsInteger','numberIsSafeInteger','numberTruthy','numberAbsolute']
    def raw(v):return struct.unpack('>Q',struct.pack('>d',v))[0]
    pairs=[(.1,.2),(-0.,0.),(float('inf'),float('-inf')),(float('nan'),1.),(1.,3.),(-5.5,2.),(2.**53,1.),(5e-324,2.),(1.7976931348623157e308,2.)]
    pairs += [(0., -0.), (-0., -0.), (1., 2.**-53), (-1., -2.**-53), (2.**-1022, 5e-324), (-1.7976931348623157e308, 2.), (2.**53-1, 1.)]
    generator = random.Random(20261117)
    for _ in range(9):
        pairs.append(tuple(struct.unpack('>d', generator.getrandbits(64).to_bytes(8, 'big'))[0] for _ in range(2)))
    cases=[{'op':o,'a':f'{raw(a):016x}','b':f'{raw(b):016x}'} for o in ops for a,b in pairs]
    (p/'cases.json').write_text(json.dumps(cases))
    (p/'native.js').write_text('''const fs=require('fs'); const rows=JSON.parse(fs.readFileSync(process.argv[2]));const buffer=new ArrayBuffer(8), view=new DataView(buffer);const decode=h=>{view.setBigUint64(0,BigInt('0x'+h));return view.getFloat64(0)};const encode=x=>{if(Number.isNaN(x))return '7ff8000000000000';view.setFloat64(0,x);return view.getBigUint64(0).toString(16).padStart(16,'0')};console.log(JSON.stringify(rows.map(c=>{const a=decode(c.a),b=decode(c.b);let x;switch(c.op){case 'numberAdd':x=a+b;break;case 'numberSubtract':x=a-b;break;case 'numberMultiply':x=a*b;break;case 'numberDivide':x=a/b;break;case 'numberRemainder':x=a%b;break;case 'numberNegate':x=-a;break;case 'numberAbsolute':x=Math.abs(a);break;case 'numberEqual':x=a===b;break;case 'numberLessThan':x=a<b;break;case 'numberLessEqual':x=a<=b;break;case 'numberSameValue':x=Object.is(a,b);break;case 'numberIsNaN':x=Number.isNaN(a);break;case 'numberIsFinite':x=Number.isFinite(a);break;case 'numberIsInteger':x=Number.isInteger(a);break;case 'numberIsSafeInteger':x=Number.isSafeInteger(a);break;case 'numberTruthy':x=!!a;break;}return {...c, width:typeof x==='boolean'?1:64,result:typeof x==='boolean'?(x?'1':'0'):encode(x)}})));''')
    rows=json.loads(run(['node',p/'native.js',p/'cases.json']));(p/'expected.json').write_text(json.dumps(rows,indent=2))
    assert json.loads(run(['bun', 'run', '--no-install', p/'native.js', p/'cases.json'])) == rows
    shutil.copy2(root/'Semantics/Lean/SwiftFormal/Runtime.lean',p/'Runtime.lean')
    shutil.copy2(root/'Sources/FormalCompiler/TLA/Emission/SwiftFormalRuntime.tla',p/'SwiftFormalRuntime.tla')
    s='import Runtime\nopen SwiftFormal\nset_option maxRecDepth 8192\nset_option maxHeartbeats 2000000\n'
    for i,c in enumerate(rows):
     v=int(c['result'],16) if c['width']==64 else int(c['result'])
     s+=f"theorem case{i} : numberBinary .{c['op']} {int(c['a'],16)} {int(c['b'],16)} = some (.bits {c['width']} {v}) := by rfl\n#print axioms case{i}\n"
    (p/'Checks.lean').write_text(s)
    def bits(h,width=64):
     value=int(h,16) if width==64 else int(h)
     return f'Bits({width},<<'+','.join(str((value>>i)&1) for i in range(width))+'>>)'
    cases_text=',\n'.join(f'[op |-> "{c["op"]}", a |-> {bits(c["a"])}, b |-> {bits(c["b"])}, expected |-> {bits(c["result"],c["width"])}]' for c in rows)
    (p/'Checks.tla').write_text('---- MODULE Checks ----\nEXTENDS SwiftFormalRuntime\nVARIABLE index\nRows == <<'+cases_text+'>>\nInit == index = 1\nNext == IF index < Len(Rows) THEN index\' = index + 1 ELSE UNCHANGED index\nLegacyOperators == Binary("equal", Bits(1,<<0>>), Bits(1,<<0>>)) = Flag(TRUE) /\\ Binary("xor", Bits(1,<<1>>), Bits(1,<<1>>)) = Flag(FALSE) /\\ Binary("and", Bits(1,<<0>>), Bits(1,<<1>>)) = Flag(FALSE) /\\ Binary("or", Bits(1,<<0>>), Bits(1,<<1>>)) = Flag(TRUE)\nExpected == LegacyOperators /\\ Binary(Rows[index].op,Rows[index].a,Rows[index].b) = Rows[index].expected\n====\n')
    (p/'Checks.cfg').write_text('INIT Init\nNEXT Next\nINVARIANT Expected\n')
    run(['swift', 'test', '--filter', 'NumberArithmeticTests'], env={**os.environ, 'FORMAL_NUMBER_CASES': str(p/'expected.json')})
    environment = {**os.environ, 'LEAN_PATH': str(p)}
    run([lean, '-M', '1024', '-o', 'Runtime.olean', 'Runtime.lean'], cwd=p, env=environment)
    audit = run([lean, '-M', '1024', 'Checks.lean'], cwd=p, env=environment, timeout=300)
    assert 'sorry' not in audit.lower() and 'error:' not in audit
    assert sum('depends on axioms:' in line or 'does not depend on any axioms' in line for line in audit.splitlines()) == len(rows)
    for line in audit.splitlines():
        if 'depends on axioms:' in line:
            assert set(line.split('[')[1].rstrip(']').replace(' ', '').split(',')) <= {'propext','Classical.choice','Quot.sound'}
    (p/'lean.log').write_text(audit)
    tlc = run([java, '-Xss32m', '-Xmx512m', '-cp', jar, 'tlc2.TLC', '-workers', '1', '-cleanup', 'Checks'], cwd=p, timeout=300)
    (p/'tlc.log').write_text(tlc)
    assert 'Model checking completed. No error has been found.' in tlc
    print('PASS', len(rows), 'Node/Bun/SwiftIR/Lean/TLC Number vectors', flush=True)
    records.append({'scope':'component', 'vectors':len(rows)})


def native_source(directory, source, arguments):
    decoder = "x=>{if(x.startsWith('bits:')){v.setBigUint64(0,BigInt('0x'+x.slice(5)));return v.getFloat64(0)}return Number(x)}"
    encoder = "x=>{if(typeof x==='boolean')return x?'true':'false';if(Number.isNaN(x))return 'bits:7ff8000000000000';v.setFloat64(0,x);return 'bits:'+v.getBigUint64(0).toString(16).padStart(16,'0')}"
    path = directory/'native.ts'
    path.write_text(source + '\nconst v=new DataView(new ArrayBuffer(8));const decode=' + decoder + ';const encode=' + encoder + ';console.log(JSON.stringify(' + json.dumps(arguments) + '.map(xs=>encode(calculate(...xs.map(decode))))));')
    node = json.loads(run(['node', '--experimental-strip-types', path]))
    bun = json.loads(run(['bun', 'run', '--no-install', path]))
    assert node == bun
    return node


def finite(name, language, source, arguments, result_view='number'):
    if selection is not None: return
    directory = work/name; directory.mkdir()
    expected = native_source(directory, source, arguments)
    (directory/'source').write_text(source)
    scenario = {'schemaVersion':1,'fuel':64,'cases':[
        {'name':f'case{i}','entry':'calculate','arguments':values,'inputViews':['number']*len(values),
         'resultView':result_view,'expected':{'status':'returned','value':value}}
        for i,(values,value) in enumerate(zip(arguments,expected))]}
    (directory/'cases.json').write_text(json.dumps(scenario,indent=2))
    report = json.loads(run([formal,'check','--language',language,'--source',directory/'source',
        '--scenario',directory/'cases.json','--output',directory/'Checked'],timeout=300))
    (directory/'result.json').write_text(json.dumps(report,indent=2))
    for case in report['cases']:
        assert case['irMatchesExpected'] and case['lean']=='PROVED' and case['tlc']=='MODEL_CHECKED',report
    assert report['translation']=='UNVALIDATED'
    records.append({'name':name,'scope':'SOURCE_IR_LEAN_TLC','cases':len(arguments)})
    print('PASS',name,'native/IR/Lean/TLC',flush=True)


def property_check(name, language, source, views, result_view, ensures, requires='true', status='PROVED'):
    if selection is not None and name not in selection: return None, None
    executed.append(name)
    directory = work/name; directory.mkdir()
    (directory/'source').write_text(source)
    specification={'schemaVersion':1,'properties':[{'name':name,'entry':'calculate','inputViews':views,
        'resultView':result_view,'requires':requires,'ensures':ensures}]}
    (directory/'properties.json').write_text(json.dumps(specification,indent=2))
    report=json.loads(run([formal,'check','--language',language,'--source',directory/'source',
        '--properties',directory/'properties.json','--output',directory/'Checked'],expected=5 if status=='COUNTEREXAMPLE' else 0))
    (directory/'result.json').write_text(json.dumps(report,indent=2))
    item=report['properties'][0]
    assert item['status']==status and item['tla']=='SPECIFICATION_GENERATED',report
    assert report['scope']=='ALL_INPUTS_UNDER_PRECONDITIONS' and report['translation']=='UNVALIDATED'
    assert set(item['leanAxioms']) <= {'propext','Classical.choice','Quot.sound'}
    if status=='COUNTEREXAMPLE':
        assert item['lean']=='COUNTEREXAMPLE_PROVED' and item['counterexampleTLC']=='COUNTEREXAMPLE'
        values=native_source(directory,source,[item['counterexample']])
        (directory/'native-witness.json').write_text(json.dumps(values))
        native_case = {'schemaVersion': 1, 'fuel': item['executionBound'], 'cases': [{
            'name': 'native_witness', 'entry': 'calculate', 'arguments': item['counterexample'],
            'inputViews': views, 'resultView': result_view,
            'expected': {'status': 'returned', 'value': values[0]}}]}
        (directory/'native-case.json').write_text(json.dumps(native_case))
        observed = json.loads(run([formal, 'check', '--artifact', directory/'Checked',
            '--scenario', directory/'native-case.json'], timeout=300))
        witness = observed['cases'][0]
        assert witness['irMatchesExpected'] and witness['lean'] == 'PROVED' and witness['tlc'] == 'MODEL_CHECKED'
        (directory/'native-case-result.json').write_text(json.dumps(observed, indent=2))
    else: assert item['lean']=='PROVED'
    records.append({'name':name,'scope':report['scope'],'status':status})
    print('PASS',name,status,flush=True)
    return report,directory


if selection is None:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        futures = [
            pool.submit(finite, 'rounding', 'bun', 'function calculate(a: number,b: number){return a+b;}', [['.1','.2'],['9007199254740992','1']]),
            pool.submit(finite, 'negation', 'javascript', 'function calculate(a){return -a}', [['0'],['-0'],['NaN']]),
        ]
        for future in futures: future.result()
finite('division','typescript','function calculate(a: number,b: number): number {return a/b}',[['1','0'],['0','0'],['-0','1'],['1','3']])
finite('remainder','bun','function calculate(a,b){return a%b}',[['-5.5','2'],['5e-324','2'],['Infinity','2']])
finite('truthiness','javascript','function calculate(a){if(a){return true}else{return false}}',[['NaN'],['-0'],['Infinity'],['.1']],'boolean')
finite('short_circuit','bun','function calculate(a){return a || 2;}',[['NaN'],['-0'],['-1'],['Infinity']])
finite('classification_guard','typescript','function calculate(a: number){return Number.isFinite(a) && a>=0;}',[['NaN'],['Infinity'],['-1'],['.5']],'boolean')
finite('logical_not','javascript','function calculate(a){return !a;}',[['NaN'],['-0'],['Infinity'],['.1']],'boolean')
finite('inequality','bun','function calculate(a,b){return a!==b;}',[['NaN','NaN'],['-0','0'],['1','2'],['1','1']],'boolean')
finite('nan_comparison','typescript','function calculate(a: number,b: number){return a<=b}',[['NaN','0'],['-0','0'],['1','2']],'boolean')
identity,_=property_check('identity','bun','function calculate(a){return a;}', ['number'],'number','sameValue(result,arg0)')
property_check('irreflexive','javascript','function calculate(a){return a<a;}', ['number'],'boolean','result == false')
property_check('reflexive_without_nan','typescript','function calculate(a: number){return a===a;}', ['number'],'boolean','isNaN(arg0) || result')
addition,addition_directory=property_check('addition','bun','function calculate(a: number,b: number){return a+b;}', ['number','number'],'number','sameValue(result,arg0+arg1)')
property_check('negation_all_inputs','javascript','function calculate(a){return -a;}', ['number'],'number','sameValue(result,-arg0)')
property_check('rounding_counterexample','bun','function calculate(){return .1+.2;}', [],'number','result == .3',status='COUNTEREXAMPLE')
property_check('nan_counterexample','javascript','function calculate(a){return a-a;}', ['number'],'number','result == 0',status='COUNTEREXAMPLE')
property_check('reflexivity_counterexample','typescript','function calculate(a: number){return a===a;}', ['number'],'boolean','result',status='COUNTEREXAMPLE')
property_check('precision_counterexample','bun','function calculate(a){return a+1;}', ['number'],'number','result > arg0',requires='arg0 == 9007199254740992',status='COUNTEREXAMPLE')
if addition is not None:
    # Mutate the actual generated program while keeping the quantified specification unchanged.
    mutation=work/'mutation';shutil.copytree(Path(addition['runDirectory'])/'lean',mutation)
    program=mutation/'Generated/Program.lean';text=program.read_text();assert '.numberAdd' in text
    program.write_text(text.replace('.numberAdd','.numberSubtract'))
    mutation_env={**os.environ,'LEAN_PATH':str(mutation)}
    run([lean,'-M','1024','-o','Generated/Program.olean','Generated/Program.lean'],cwd=mutation,env=mutation_env)
    rejected=run([lean,'-M','2048','Property0.lean'],expected=1,cwd=mutation,env=mutation_env)
    assert 'error:' in rejected and 'sorryAx' in rejected
    print('PASS actual_Number_program_mutation_rejected',flush=True)
assert selection is None or selection <= set(executed), 'Unknown property selection'
summary={'status':'PASSED','checks':records,'nativeVersions':{'node':run(['node','--version']).strip(),'bun':run(['bun','--version']).strip()}}
(work/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary,indent=2))
if not args.output: shutil.rmtree(work)
