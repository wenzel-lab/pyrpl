from ..attributes import *
from ..modules import HardwareModule
from ..widgets.module_widgets.FadsWidget import FadsWidget


class FADS(HardwareModule):
    """
    Implementing fluorescence activated droplet sorting
    """
    addr_base = 0x40600000
    name = 'FADS'
    _widget_class = FadsWidget

    _gui_attributes = ["low_threshold",
                       "high_threshold"]

    _setup_attributes = _gui_attributes

    _adc_bits = 14

    low_threshold = FloatRegister(0x0, bits=_adc_bits, norm=2 ** 13,
                                  doc="low threshold for sorting")
    high_threshold = FloatRegister(0x4, bits=_adc_bits, norm=2 ** 13,
                                   doc="low threshold for sorting")

    # def __init__(self, parent):
    #     super().__init__(parent)
    #
    #     while True:
    #         print(self.get_state())

    # def get_state(self):
    #     print("retrieving state")
    #     state = self._read(0)
    #     return state

    # state = BoolRegister(0x0, 0, doc="Current state")
