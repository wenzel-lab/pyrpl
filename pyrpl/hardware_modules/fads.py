from ..attributes import *
from ..modules import HardwareModule


class FADS(HardwareModule):
    """
    Implementing fluorescence activated droplet sorting
    """
    addr_base = 0x40600000

    # def __init__(self, parent):
    #     super().__init__(parent)
    #
    #     while True:
    #         print(self.get_state())

    # def get_state(self):
    #     print("retrieving state")
    #     state = self._read(0)
    #     return state

    state = BoolRegister(0x0, 0, doc="Current state")
