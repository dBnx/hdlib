
## How to install

- Add this library to your git-based project as a submodule via:
```sh
git submodule add https://gitlab.com/dBnx/primitives external/primitives 
```
- Add all SystemVerilog sources to your project.


## Run tests


### Install dependencies

- Install Python 3, venv and `verilator` (or another [cocotb](https://github.com/cocotb/cocotb) backend)
  - Via pacman on Arch-based linux distributions:
```sh
sudo pacman -S python verilator
```
- (Optional, recommended) Create a virtual environment 
```sh
python -m venv venv
```
- Install python requirements
  - Via pip
```sh
python -m pip install -r requirements.txt
```
  - Via pacman on Arch-based linux distributions:
```sh
sudo pacman -S python-cocotb python-pytest python-pytest-xdist python-pytest-cov
```

`pytest-xdist` is not strictly necessary, but recommended to speed it up by a huge margin and thus added to requirements.txt


### Dendencies

- Without `pytest-xdist`:
```sh
pytest --last-failed
```
- With `pytest-xdist`:
```sh
pytest -n auto --dist worksteal --last-failed
```
Intstead of auto a custom number of parallel processes can be used.


## About the structure of the project

Ever module `module` has an associated 
- `module.sv` file with the implementation
- `module_test.py` containing cocotb unit tests
- `module.sav` that contains an (optional) GTKwave layout for easy inspection of trace dumps

Those files can be found in the appropriate subfolder. All of the contained modules may depend on any other module. This
is (for now - due to rapid changes) not documented and a user of this library may assume total interdependence. Meaning
all files should be added in a project to guarantee succesfull compilation.

Contained modules may also depend on other libraries, those are mentioned in the _How to install_ section above.
