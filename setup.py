from setuptools import setup, find_packages


def parse_requirements(filename):
    with open(filename, "r") as file:
        return [line.strip() for line in file if line.strip()]


setup(
    name="gits",
    description="CLI program to schedule git push or commit commands for execution at a specified time",
    version="1.0",
    author="mahmoud barazi",
    packages=find_packages(),
    install_requires=parse_requirements("requirements.txt"),
    entry_points="""
        [console_scripts]
        gits=src.gits:gits
    """,
)
