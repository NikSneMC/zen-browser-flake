#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3.pkgs.requests
from concurrent.futures import Future, ThreadPoolExecutor, as_completed
from json import loads, load, dump
from os import cpu_count
from subprocess import PIPE, run
from typing import Callable, TypedDict
from requests import get


class Asset(TypedDict):
    name: str
    browser_download_url: str


class RawVersion(TypedDict):
    name: str
    published_at: str
    assets: list[Asset]


class VersionInfo(TypedDict):
    version: str
    published_at: str
    channel: str


class Download(TypedDict):
    url: str
    hash: str


Downloads = dict[str, Download]


class Version(TypedDict):
    info: VersionInfo
    downloads: Downloads


Systems = list[str]
Channels = dict[str, str]
Versions = dict[str, Version]


class Info(TypedDict):
    systems: Systems
    channels: Channels
    versions: Versions


def parse_version_info(version: RawVersion) -> VersionInfo:
    version_str: str = version["name"].split(" - ")[1].split(" (")[0]
    version_splitted = version_str.split("-")
    if len(version_splitted) == 2:
        channel = version_splitted[1][0]
    else:
        channel = version_splitted[0][-1]
    return VersionInfo(
        version=version_str, published_at=version["published_at"], channel=channel
    )


def process_url(url: str) -> Download:
    file_str: str = " (".join(url.split("/")[-1:-3:-1]) + ")"
    print(f"Computing hash for {file_str}")
    hash: str = loads(
        run(
            f"nix store prefetch-file {url} --log-format raw --json".split(),
            stdout=PIPE,
        ).stdout.decode("utf-8")
    )["hash"]
    print(f"Hash for {file_str} is {hash}")
    return Download(url=url, hash=hash)


def fetch_downloads(raw_version: RawVersion, old_info: Info) -> Downloads:
    with ThreadPoolExecutor(max_workers=len(old_info["systems"])) as executor:
        future_to_system: dict[Future[Download], str] = {}
        for asset in raw_version["assets"]:
            for system in old_info["systems"]:
                if asset["name"] not in [
                    f"zen.{system}.{ext}" for ext in ("tar.bz2", "tar.xz")
                ]:
                    continue
                url: str = asset["browser_download_url"]
                future_to_system[executor.submit(process_url, url)] = system
        downloads: Downloads = {}
        for future in as_completed(future_to_system):
            downloads[future_to_system[future]] = future.result()
    return Downloads(sorted(downloads.items()))


def parse_versions(old_info: Info) -> Callable[[RawVersion], tuple[str, Version]]:
    def parse_version(raw_version: RawVersion) -> tuple[str, Version]:
        version_info = parse_version_info(raw_version)
        if (
            version_info["channel"] != "t"
            and version_info["version"] in old_info["versions"].keys()
        ):
            version = old_info["versions"][version_info["version"]]
        else:
            print(f"Found new version: {version_info['version']}")
            version = Version(
                info=version_info, downloads=fetch_downloads(raw_version, old_info)
            )
        return version["info"]["version"], version

    return parse_version


def get_info(old_info: Info) -> Info:
    raw_versions: list[RawVersion] = []
    page: int = 1
    while 1:
        raw_versions_page: list[RawVersion] | RawVersion = get(
            f"https://api.github.com/repos/zen-browser/desktop/releases?per_page=100&page={page}"
        ).json()

        if isinstance(raw_versions_page, dict):
            raw_versions_page = [raw_versions_page]

        if len(raw_versions_page) == 0:
            break

        raw_versions.extend(raw_versions_page)
        page += 1

    with ThreadPoolExecutor(max_workers=(cpu_count() or 1) * 4) as executor:
        futures: list[Future[tuple[str, Version]]] = []
        for raw_version in raw_versions:
            futures.append(executor.submit(parse_versions(old_info), raw_version))
        versions: Versions = {}
        for future in as_completed(futures):
            version_name, version = future.result()
            versions[version_name] = version
    versions = Versions(
        sorted(
            [*old_info["versions"].items(), *versions.items()],
            key=lambda v: v[1]["info"]["published_at"],
            reverse=True,
        )
    )
    channels_map = dict(map(lambda c: (c[0], c), old_info["channels"].keys()))
    channels: Channels = {}
    for version in versions.values():
        if len(channels) == len(old_info["channels"]):
            break
        channel: str = channels_map[version["info"]["channel"]]
        if channel in channels.keys():
            continue
        channels[channel] = version["info"]["version"]

    return Info(systems=old_info["systems"], channels=channels, versions=versions)


def main(info_file: str) -> None:
    with open(file=info_file, mode="r", encoding="utf-8") as f:
        old_info: Info = Info(**load(f))  # pyright: ignore[reportAny]

    new_info = get_info(old_info)

    if old_info != new_info:
        with open(file=info_file, mode="w", encoding="utf-8") as f:
            dump(new_info, f, indent=2)
    else:
        print("Zen Browser is up-to-date")


if __name__ == "__main__":
    main("./info.json")
