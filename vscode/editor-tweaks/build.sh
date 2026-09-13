#!/usr/bin/env bash
# Package the editor-tweaks extension into a .vsix and install it into VS Code.
# Needed on a fresh machine, or after a version bump. For day-to-day edits on a
# machine where extension.js is symlinked into ~/.vscode/extensions, just edit
# this file and reload VS Code — no rebuild required.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
[ -x "$CODE_CLI" ] || CODE_CLI="$(command -v code || true)"
[ -n "$CODE_CLI" ] || { echo "no 'code' CLI found"; exit 1; }

VER="$(node -e "console.log(require('$DIR/package.json').version)")"
ID="$(node -e "console.log(require('$DIR/package.json').name)")"
BUILD="$(mktemp -d)"
mkdir -p "$BUILD/extension"
cp "$DIR/extension.js" "$DIR/package.json" "$BUILD/extension/"

cat > "$BUILD/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="${ID}" Version="${VER}" Publisher="sam" />
    <DisplayName>Editor tweaks</DisplayName>
    <Description xml:space="preserve">comment move-down + indent-aware arrows/enter</Description>
    <Tags></Tags><Categories>Other</Categories><GalleryFlags>Public</GalleryFlags>
    <Properties><Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.74.0" /></Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code" /></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" /></Assets>
</PackageManifest>
XML

cat > "$BUILD/[Content_Types].xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="json" ContentType="application/json"/>
  <Default Extension="js" ContentType="application/javascript"/>
  <Default Extension="vsixmanifest" ContentType="text/xml"/>
</Types>
XML

( cd "$BUILD" && zip -r -X ext.vsix '[Content_Types].xml' extension.vsixmanifest extension >/dev/null )
"$CODE_CLI" --install-extension "$BUILD/ext.vsix"
rm -rf "$BUILD"
echo "Installed ${ID} v${VER}. Reload VS Code."
