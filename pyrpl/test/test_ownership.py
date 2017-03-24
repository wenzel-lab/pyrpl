import logging
logger = logging.getLogger(name=__name__)
from PyQt4 import QtGui
from .test_base import TestPyrpl
from pyrpl.software_modules.module_managers import ModuleManager
APP = QtGui.QApplication.instance()


class TestOwnership(TestPyrpl):
    def test_ownership_restored(self):
        # make sure scope rolling_mode and running states are correctly setup
        # when something is changed
        if self.r is None:
            return
        self.pyrpl.networkanalyzer.iq.free()
        # otherwise not a single iq is left for test

        for module in self.pyrpl.modules:
            if isinstance(module, ModuleManager):
                with module.pop("foo") as mod:
                    assert(mod.owner=='foo')
                assert(mod.owner==None)
