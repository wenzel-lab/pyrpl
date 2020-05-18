"""
A widget for the FADS module
"""

from .base_module_widget import ModuleWidget

from qtpy import QtCore, QtWidgets


class FadsWidget(ModuleWidget):
    def __init__(self, *args, **kwds):
        super(FadsWidget, self).__init__(*args, **kwds)
