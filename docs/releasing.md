# Releasing

A release is two ZIPs built from one git tag:

| ZIP | Contents | Published at |
| --- | --- | --- |
| `portable-toolkit.zip` | The participant files: `GUI.cmd`, `SETUP.cmd`, `README.txt`, `SKILL.md`, `toolkit/` | GitHub release asset; also `https://sankara.net/downloads/portable-toolkit/portable-toolkit-v<version>.zip` |
| `portable-toolkit-offline-win313-v<version>.zip` | The same files plus 45 pinned CPython 3.13 wheels in `offline-wheels/win_amd64-cp313/` | `https://sankara.net/downloads/portable-toolkit/` only |

`tools/build_release.py` builds both. The same tag and wheels give
byte-identical ZIPs: the files come from `git archive`, which applies
`.gitattributes` line endings, and every entry is dated with the tagged
commit's date. The wheels can come straight from PyPI, so a release can be
rebuilt from public sources alone. The script uses only the standard library.

## Steps

1. Run the tests under Windows PowerShell 5.1 (Pester 3.4) from the repository
   root:

   ```
   powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Pester tests"
   ```

2. Set `version` in `toolkit/tools.json`, and update the offline download link
   in `README.md` to the new file name. Commit, then tag and push:

   ```
   git tag -a v<version> -m "portable-toolkit <version>"
   git push origin main v<version>
   ```

3. Build both ZIPs:

   ```
   uv run --no-project tools/build_release.py regular v<version> portable-toolkit.zip
   uv run --no-project tools/build_release.py offline portable-toolkit.zip pypi portable-toolkit-offline-win313-v<version>.zip
   ```

   In place of `pypi`, a previous offline ZIP can supply the wheels when the
   pinned set has not changed. Either way, the build stops unless every wheel
   matches `toolkit/offline-win313.sha256` and the set of wheels matches that
   list exactly.

4. Copy both ZIPs to the download server's `portable-toolkit` folder under
   new names (`portable-toolkit-v<version>.zip` and the offline name), mode
   644. Never overwrite an earlier version's file.

5. Create the GitHub release with `portable-toolkit.zip` as its asset. The notes
   have this order:
   1. **Download**: a direct link to the regular ZIP, for everyone.
   2. **What is new**.
   3. **Offline document bundle**: labelled as being only for when PyPI
      downloads time out, with its link and its Python 3.13 requirement.
   4. **SHA-256** of both ZIPs.

6. Verify: download both ZIPs from their public URLs and compare their SHA-256
   with the built files, and check that
   `https://github.com/kvsankar-ai-training/portable-toolkit/releases/latest/download/portable-toolkit.zip`
   resolves.

## Changing the offline wheels

`toolkit/offline-win313.lock` pins the packages, and
`toolkit/offline-win313.sha256` lists the exact wheel files and their hashes.
To change the set, update those two files and
`toolkit/offline-win313-NOTICES.txt` in one commit, then build with `pypi` as
the wheel source.
