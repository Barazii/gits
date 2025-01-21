from setuptools import setup, find_packages

setup(
    name='gits',
    version='1.0',
    packages=find_packages(),
    install_requires=[
        'schedule',
    ],
    entry_points='''
        [console_scripts]
        gits=src.gits:gits
    ''',
)