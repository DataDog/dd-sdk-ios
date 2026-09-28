"""Reject delivered input without the source-defined native effect."""
import copy
import unittest
import human_journey as journey
import test_human_contract as fixtures


class NativeEffectControls(unittest.TestCase):
    def setUp(self):
        fixture=fixtures.NativeInputControls();fixture.setUp();self.binding=fixture.binding
        self.rows=fixture.measured_rows();self.before=self.rows[2];self.after=self.rows[-2]
        self.before['payload']['phase']='initial.root.tap.before';self.after['payload']['phase']='initial.root.tap.effect'
        for row,count in [(self.before,0),(self.after,1)]:
            row['payload']['topology']['accessibility'] += [
                {'identifier':'screen.home','label':'home','frame_in_window':[0,0,400,40]},
                {'identifier':'home.receipt','label':'nil','text':'receipt:'+str(count),'frame_in_window':[10,400,300,40]}]
        self.step=journey.flow('stack','initial')[0]
    def evaluate(self,framework='UIKit'):return journey.effect(self.rows,self.before,self.after,self.step,self.binding,framework)
    def test_exact_native_state_effect(self):self.assertEqual(self.evaluate()['kind'],'tap')
    def test_callback_without_one_state_change_rejected(self):
        for count in [0,2]:
            self.after['payload']['topology']['accessibility'][-1]['text']='receipt:'+str(count)
            with self.subTest(count=count),self.assertRaises(ValueError):self.evaluate()
    def test_uikit_accessibility_label_cannot_replace_missing_text(self):
        for row,count in [(self.before,0),(self.after,1)]:
            control=row['payload']['topology']['accessibility'][-1]
            control.pop('text');control['label']='receipt:'+str(count)
        with self.assertRaisesRegex(ValueError,'native counter missing'):self.evaluate()
    def test_uikit_label_increment_cannot_hide_unchanged_text(self):
        self.before['payload']['topology']['accessibility'][-1]['label']='receipt:0'
        control=self.after['payload']['topology']['accessibility'][-1]
        control.update(label='receipt:1',text='receipt:0')
        with self.assertRaisesRegex(ValueError,'state exactly once'):self.evaluate()
    def test_malformed_uikit_text_is_rejected(self):
        for text in [None,True,1,'nil','receipt:-1','receipt:1 extra']:
            self.after['payload']['topology']['accessibility'][-1]['text']=text
            with self.subTest(text=text),self.assertRaisesRegex(ValueError,'native counter missing'):self.evaluate()
    def swiftui_counter(self):
        for row,count in [(self.before,0),(self.after,1)]:
            control=row['payload']['topology']['accessibility'][-1]
            control.pop('text');control['label']='receipt:'+str(count)
    def test_swiftui_reads_accessibility_label_without_uikit_text(self):
        self.swiftui_counter();self.assertEqual(self.evaluate('SwiftUI')['kind'],'tap')
    def test_swiftui_text_cannot_replace_missing_accessibility_label(self):
        self.swiftui_counter()
        for row,count in [(self.before,0),(self.after,1)]:
            control=row['payload']['topology']['accessibility'][-1]
            control['label']='nil';control['text']='receipt:'+str(count)
        with self.assertRaisesRegex(ValueError,'native counter missing'):self.evaluate('SwiftUI')
    def test_wrong_phase_cannot_reuse_fresh_callback(self):
        self.after['payload']['phase']='next.effect'
        with self.assertRaises(ValueError):self.evaluate()
    def test_missing_destination_screen_rejected(self):
        self.after['payload']['topology']['accessibility'].pop(-2)
        with self.assertRaises(ValueError):self.evaluate()
    def test_finite_regular_and_duo_order(self):
        regular=journey.steps('stack',False);duo=journey.steps('split',True)
        self.assertEqual(len(regular),14);self.assertEqual(len(duo),33)
        self.assertEqual([s['pose'] for s in duo if s['kind']=='fold'],['open','close','reopen'])
        self.assertEqual(len({s['phase'] for s in duo}),len(duo))
        self.assertEqual(duo[-1],{'phase':'background','kind':'home'})

if __name__=='__main__':unittest.main()
