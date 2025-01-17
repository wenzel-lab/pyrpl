"""
Script to launch pyrpl from the command line.
Type python run_pyrpl [config_file_name]
To create a Pyrpl instance with the config file "config_file_name"
"""
from pyrpl import Pyrpl
from qtpy import QtCore, QtWidgets
import sys

if __name__ == '__main__':
    """
    Script to launch pyrpl from the command line.

    Type python -m pyrpl [config_file_name] to create
    a Pyrpl instance with the config file
    "config_file_name"
    """
    if len(sys.argv) > 3:
        print("usage: python run_pyrpl.py [[config]=config_file_name] "
              "[source=config_file_template] [hostname=hostname/ip]")
    kwargs = dict()
    for i, arg in enumerate(sys.argv):
        print (i, arg)
        if i == 0:
            continue
        try:
            k, v = arg.split('=', 1)
        except ValueError:
            k, v = arg, ""
        if v == "":
            if i == 1:
                kwargs["config"] = k
        else:
            kwargs[k] = v
    APP = QtWidgets.QApplication.instance()
    if APP is None:
        APP = QtWidgets.QApplication(sys.argv)

    print("Calling Pyrpl(**%s)"%str(kwargs))
    PYRPL = Pyrpl(**kwargs)

    # while True:
    #     print(f"\r{PYRPL.rp.scope.voltage_in1}", end="")
    # print(PYRPL.rp.fads.state)
    # print()
    APP.exec_()
