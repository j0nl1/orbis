# FreeRDP integration patch

`orbis-apple.patch` contains the Orbis changes to FreeRDP's macOS and iOS
adapters. It applies to the exact commit pinned by `vendor/freerdp`:

```text
5370fb26fbf034ecd11d3026b6ad639b5fff493f  FreeRDP 3.28.0
```

The build never changes the submodule. `scripts/prepare-freerdp.sh` exports the
pinned tree to `.build/vendor/freerdp`, verifies the patch, applies it there, and
links the Orbis-owned application sources into that ignored build tree.

The patch is a derivative of FreeRDP and remains under
[Apache-2.0](../../LICENSES/Apache-2.0.txt). Orbis-owned application sources
outside the patch are under the MIT License.

When updating FreeRDP, change the submodule commit and regenerate the patch from
the reviewed adapter changes. A build must fail if the patch no longer applies
cleanly; do not resolve drift by editing the prepared copy.
