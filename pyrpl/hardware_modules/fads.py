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

    _gui_attributes = ["min_intensity_threshold",
                       "low_intensity_threshold",
                       "high_intensity_threshold",
                       "min_width_threshold",
                       "low_width_threshold",
                       "high_width_threshold"]

    _setup_attributes = _gui_attributes

    _adc_bits = 14
    _mem_bits = 32

    min_intensity_threshold = FloatRegister(0x0, bits=_adc_bits, norm=2 ** 13 / 20,
                                            doc="minimum intensity for a signal to be registered as a droplet")
    low_intensity_threshold = FloatRegister(0x4, bits=_adc_bits, norm=2 ** 13 / 20,
                                            doc="minimum intensity for a droplet to be sorted")
    high_intensity_threshold = FloatRegister(0x8, bits=_adc_bits, norm=2 ** 13 / 20,
                                             doc="maximum intensity for a droplet to be sorted")

    min_width_threshold = IntRegister(0x10, bits=_mem_bits,
                                      doc="minimum width for a signal to be registered as a droplet")
    low_width_threshold = IntRegister(0x14, bits=_mem_bits,
                                      doc="minimum width for a droplet to be sorted")
    high_width_threshold = IntRegister(0x18, bits=_mem_bits,
                                       doc="maximum width for a droplet to be sorted")

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
