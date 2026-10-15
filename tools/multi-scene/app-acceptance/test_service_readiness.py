"""Source-bound Services readiness; a permission error is not navigation coverage."""
import copy
import unittest
import time
from unittest.mock import Mock, patch

import journey_driver

import journey_phases as phases


def loaded():
    return [dict(AXLabel='Services', type='StaticText'),
            dict(AXLabel='ios-benchmark, 1 OK monitors, not favorited, env: prod',
                 type='Button', enabled=True, frame=dict(x=10, y=80, width=250, height=60))]


class ServiceReadinessControls(unittest.TestCase):
    def test_real_row_qualifies_with_optional_monitor_status(self):
        self.assertTrue(phases.service_list_loaded(loaded(), 'ios-benchmark'))
        value=loaded();value[1]['AXLabel']='ios-benchmark, favorited'
        self.assertTrue(phases.service_list_loaded(value, 'ios-benchmark'))

    def test_permission_shell_loading_empty_and_wrong_service_do_not_qualify(self):
        for value in [loaded()[:1], loaded()[:1]+[dict(AXLabel='No results')],
                      loaded()+[dict(AXLabel='apm_service_catalog_read Permission Required')],
                      [dict(AXLabel='Services'),dict(AXLabel='ios-benchmark')]]:
            with self.subTest(value=value):self.assertFalse(phases.service_list_loaded(value, 'ios-benchmark'))
        self.assertFalse(phases.service_list_loaded(loaded(), 'ios'))

    def test_permission_shell_never_reaches_native_readiness_or_input(self):
        driver=object.__new__(journey_driver.Driver)
        driver.deadline=time.time()+60;driver.polls=0;driver.selection={'service_label':'ios-benchmark'}
        driver.live=lambda end:None;driver.collector=Mock()
        driver.ax=Mock(side_effect=[([dict(AXLabel='Services'),
                                    dict(AXLabel='apm_service_catalog_read Permission Required')],None),
                                   RuntimeError('end of saved observations')])
        with patch.object(journey_driver.time,'sleep'):
            with self.assertRaisesRegex(RuntimeError,'end of saved observations'):
                driver.ready('service-list','list')
        driver.collector.snapshot.assert_not_called()

    def test_hidden_disabled_duplicate_and_zero_geometry_reject(self):
        for mode in ['hidden','disabled','duplicate','zero','no-title','no-frame']:
            value=copy.deepcopy(loaded())
            if mode=='hidden':value[1]['AXHidden']=True
            if mode=='disabled':value[1]['enabled']=False
            if mode=='duplicate':value.append(copy.deepcopy(value[1]))
            if mode=='zero':value[1]['frame']['width']=0
            if mode=='no-title':value.pop(0)
            if mode=='no-frame':value[1].pop('frame')
            with self.subTest(mode=mode):self.assertFalse(phases.service_list_loaded(value, 'ios-benchmark'))


if __name__=='__main__':unittest.main()
