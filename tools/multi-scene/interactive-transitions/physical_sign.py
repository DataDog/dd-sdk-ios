#!/usr/bin/env python3
"""Sign unchanged qualified physical products; retain an earlier parser failure."""
import argparse
import datetime
import fnmatch
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import time
import physical_build as original
shared=original.shared
require=original.require
verify=original.verify
HERE=original.HERE
platform=original.platform


def sign(root, profile, certificate, udid):
    root = Path(root).resolve(); plan = verify(root)
    import sys
    sys.path.insert(0, str(HERE.parent/'acceptance')); import installed_code
    p = plistlib.loads(subprocess.run(['security','cms','-D','-i',str(profile)],capture_output=True,check=True,timeout=20).stdout)
    ent = p['Entitlements']; team = ent['com.apple.developer.team-identifier']
    require(udid in p.get('ProvisionedDevices',[]) and ent.get('get-task-allow') is True, 'profile does not grant this development device')
    require(p['ExpirationDate'].replace(tzinfo=datetime.timezone.utc).timestamp()>time.time(), 'expired profile')
    require(certificate in {hashlib.sha1(c).hexdigest().upper() for c in p['DeveloperCertificates']}, 'profile/certificate mismatch')
    target = root/'signed-qualified'; target.mkdir(); result = dict(build_plan_sha256=shared.sha(root/'plan.json'),profile_sha256=shared.sha(profile),
        certificate=certificate, team=team, udid=udid, products={}, receipts={}, native_admitted=False)
    deadline = time.time()+300
    for key in ['A-device','B-device']:
        receipt = shared.read(root/key/'build-result.json')
        require(receipt['state']=='UNSIGNED_DEVICE_BUILD_QUALIFIED' and receipt['compiler']==original.original.compiled(root/key,plan['arms'][key]), 'compiler evidence changed')
        result['receipts'][key] = shared.sha(root/key/'build-result.json')
        for framework,item in receipt['products'].items():
            bundle = item['bundle']; require(fnmatch.fnmatchcase(team+'.'+bundle,ent['application-identifier']), 'profile does not grant bundle')
            require(shared.product(item['path'],bundle=bundle)==item['product'], 'unsigned product changed')
            folder=target/(key+'-'+framework);folder.mkdir();app=folder/Path(item['path']).name;shutil.copytree(item['path'],app)
            shutil.copy2(profile,app/'embedded.mobileprovision')
            entitlements=folder/'entitlements.plist';entitlements.write_bytes(plistlib.dumps({'application-identifier':team+'.'+bundle,
                'com.apple.developer.team-identifier':team,'get-task-allow':True}))
            inv=installed_code.inventory(app);require(set(inv['binaries'])=={inv['executable']},'unexpected nested code')
            shared.command(['codesign','--force','--sign',certificate,'--entitlements',str(entitlements),str(app)],folder,'sign',deadline=deadline)
            shared.command(['codesign','--verify','--deep','--strict','--verbose=2',str(app)],folder,'verify',deadline=deadline)
            shared.command(['codesign','--display','--extract-certificates='+str(folder/'cert-'),str(app)],folder,'certificate',deadline=deadline)
            require(hashlib.sha1((folder/'cert-0').read_bytes()).hexdigest().upper()==certificate,'wrong signed certificate')
            signed_entitlements=plistlib.loads(shared.capture(['codesign','--display','--entitlements','-','--xml',str(app)]).stdout)
            require(signed_entitlements==plistlib.loads(entitlements.read_bytes()),'signed entitlements differ')
            require(shared.sha(app/'embedded.mobileprovision')==shared.sha(profile),'embedded profile differs')
            result['products'][key+'-'+framework]=dict(path=str(app),bundle=bundle,product=shared.product(app,bundle=bundle),
                installed=installed_code.inventory(app),platform=platform(app,bundle),entitlements=signed_entitlements)
    verify(root); require(time.time()<deadline,'signing deadline expired')
    shared.save(target/'plan.json',result,exclusive=True)
    print(json.dumps(dict(state='SIGNED_PHYSICAL_PRODUCTS_PREPARED',products=len(result['products']),native_admitted=False)),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    parser.add_argument('--profile',type=Path,required=True);parser.add_argument('--certificate',required=True);parser.add_argument('--udid',required=True)
    args=parser.parse_args();sign(args.root,args.profile,args.certificate,args.udid)
