"""Negative controls for the source-declared simulator authentication capability."""
import copy
from pathlib import Path
import plistlib
import struct
import unittest

from signing_contract import entitlement_section, packaged_entitlements, source_entitlements, signing_inventory, signing_link_transition

TEAM='JKFCB4CN7C'
GROUP='group.com.datadog.apps-staging'
INFO={'CFBundleIdentifier':'com.datadog.flagship-staging',
      'LSEnvironment':{'APP_GROUP':GROUP,'KEYCHAIN_GROUP':TEAM+'.'+GROUP}}
DECLARED={'keychain-access-groups':['$(AppIdentifierPrefix)$(APP_GROUP)'],
          'com.apple.security.application-groups':['$(APP_GROUP)']}
EFFECTIVE={'application-identifier':TEAM+'.'+INFO['CFBundleIdentifier'],
           'keychain-access-groups':[TEAM+'.'+GROUP],
           'com.apple.security.application-groups':[GROUP]}


def macho(value, der=None):
    payloads=[(b'__entitlements',plistlib.dumps(value))]
    if der is not None:payloads.append((b'__ents_der',der))
    command_size=72+80*len(payloads)
    header=struct.pack('<IIIIIIII',0xfeedfacf,0x100000c,0,2,1,command_size,0,0)
    segment=struct.pack('<II16sQQQQIIII',0x19,command_size,b'__TEXT',0,0,0,0,0,0,len(payloads),0)
    position=32+command_size;sections=[]
    for name,data in payloads:
        sections.append(struct.pack('<16s16sQQIIIIIIII',name,b'__TEXT',0,len(data),position,0,0,0,0,0,0,0))
        position+=len(data)
    return header+segment+b''.join(sections)+b''.join(data for _,data in payloads)


def link():
    base=Path('/fresh/DerivedData')
    directory=base/'Build/Intermediates.noindex/DatadogApp.build/Debug-iphonesimulator/DatadogApp.build'
    value=['clang','-framework','DatadogRUM']
    for section,suffix in [('__entitlements',''),('__ents_der','.der')]:
        value+=['-Xlinker','-sectcreate','-Xlinker','__TEXT','-Xlinker',section,'-Xlinker',str(directory/('DatadogApp.app-Simulated.xcent'+suffix))]
    return value+['-Xlinker','-no_adhoc_codesign','-o','/app'],base


class SigningContractControls(unittest.TestCase):
    def test_source_group_and_application_identity_must_agree(self):
        self.assertEqual(source_entitlements(DECLARED,EFFECTIVE,INFO,TEAM)['keychain_group'],TEAM+'.'+GROUP)
        for key in EFFECTIVE:
            value=copy.deepcopy(EFFECTIVE);value.pop(key)
            with self.subTest(missing=key),self.assertRaises(AssertionError):
                source_entitlements(DECLARED,value,INFO,TEAM)
        for key in ['KEYCHAIN_GROUP','APP_GROUP']:
            info=copy.deepcopy(INFO);info['LSEnvironment'][key]='foreign'
            with self.subTest(key=key),self.assertRaises(AssertionError):
                source_entitlements(DECLARED,EFFECTIVE,info,TEAM)
        value=copy.deepcopy(EFFECTIVE);value['keychain-access-groups'].append('foreign')
        with self.assertRaises(AssertionError):source_entitlements(DECLARED,value,INFO,TEAM)

    def test_only_known_platform_omissions_are_allowed(self):
        declared={**DECLARED,'com.apple.security.app-sandbox':True}
        source_entitlements(declared,EFFECTIVE,INFO,TEAM)
        with self.assertRaises(AssertionError):
            source_entitlements(DECLARED,{**EFFECTIVE,'unexpected-capability':True},INFO,TEAM)
        with self.assertRaises(AssertionError):
            source_entitlements({**DECLARED,'required-new-capability':True},EFFECTIVE,INFO,TEAM)

    def test_both_embedded_xml_and_der_match_exact_packaging_inputs(self):
        xml=plistlib.dumps(EFFECTIVE);der=b'synthetic DER bytes'
        self.assertEqual(packaged_entitlements(macho(EFFECTIVE,der),xml,der),EFFECTIVE)
        for binary,x,d in [(macho(EFFECTIVE,der),xml,der+b'changed'),
                           (macho(EFFECTIVE,der),plistlib.dumps({}),der),
                           (macho(EFFECTIVE),xml,der)]:
            with self.assertRaises(AssertionError):packaged_entitlements(binary,x,d)

    def test_actual_macho_section_and_truncation(self):
        self.assertEqual(entitlement_section(macho(EFFECTIVE)),EFFECTIVE)
        for raw in [macho(EFFECTIVE)[:100],macho(EFFECTIVE)[:-1],b'not a binary']:
            with self.subTest(size=len(raw)),self.assertRaises(AssertionError):entitlement_section(raw)
        raw=bytearray(macho(EFFECTIVE));struct.pack_into('<I',raw,108+44,2**31)
        with self.assertRaises((AssertionError,plistlib.InvalidFileException)):
            entitlement_section(raw)

    def test_only_exact_linker_packaging_inputs_can_vary(self):
        value,base=link();plain,sections=signing_link_transition(value,base)
        self.assertEqual(plain,['clang','-framework','DatadogRUM','-o','/app'])
        self.assertEqual(len(sections),2)
        debug=['clang','-Xlinker','-no_adhoc_codesign','-o','debug']
        self.assertEqual(signing_link_transition(debug,base,embedded=False)[0],['clang','-o','debug'])
        with self.assertRaises(AssertionError):signing_link_transition(value,base,embedded=False)
        for changed in [value[:3]+value[11:],
                        ['foreign' if x=='__TEXT' else x for x in value],
                        [x.replace('/fresh/','/stale/') for x in value],
                        value+['-Xlinker','-no_adhoc_codesign']]:
            with self.subTest(changed=changed),self.assertRaises(AssertionError):signing_link_transition(changed,base)

    def test_signing_inventory_cannot_hide_product_changes(self):
        before={'DatadogApp':{'mode':0o755},'Info.plist':{'mode':0o644}}
        good={**before,'_CodeSignature/CodeResources':{'mode':0o644}}
        self.assertEqual(signing_inventory(good,before),['_CodeSignature/CodeResources'])
        detached={**good,**{'_CodeSignature/'+n:{'mode':0o644} for n in ['CodeDirectory','CodeRequirements','CodeSignature']}}
        self.assertEqual(len(signing_inventory(detached,before)),4)
        with self.assertRaises(AssertionError):signing_inventory({**detached,'new.bundle/_CodeSignature/CodeResources':{'mode':0o644}},before)
        for changed in [before,{**good,'injected.dylib':{'mode':0o755}},
                        {k:v for k,v in good.items() if k!='DatadogApp'},
                        {**good,'DatadogApp':{'mode':0o644}}]:
            with self.subTest(changed=changed),self.assertRaises(AssertionError):signing_inventory(changed,before)


if __name__=='__main__':unittest.main()
