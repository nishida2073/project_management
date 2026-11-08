# AVD の書き出しと読み込み

smstokintone の結合テストで使う Android Virtual Device（AVD）の設定を、別の PC に移すためのバッチです。AVD のディスクの中身（`userdata` とスナップショット）は移しません。移動先では空の状態で AVD を作り直します。

## ファイル

| ファイル | 役割 |
|---|---|
| export-avd.bat | AVD の設定ファイルを zip に書き出します（起動中のエミュレーターは停止します）。 |
| export-avd.ps1 | export-avd.bat から呼ばれる書き出しの処理です。 |
| import-avd.bat | zip から AVD の設定ファイルを読み込みます。 |
| import-avd.ps1 | import-avd.bat から呼ばれる読み込みの処理です。 |
| Pixel_6.zip | 書き出した結果です。移動先に持っていくファイルです。 |

## 書き出し（移動元の PC）

1. `export-avd.bat` を実行します。
2. `bats\avd\Pixel_6.zip` ができたことを確認します。

zip の中身は次の 2 つです。

- `Pixel_6.avd\config.ini`
- `Pixel_6.ini`

## 読み込み（移動先の PC）

1. `Pixel_6.zip` を `bats\avd\` に置きます。
2. Android Studio の SDK Manager で、次のシステムイメージを入れます。
   - Android 14.0（API 34）
   - Google APIs（x86_64）
3. `import-avd.bat` を実行します。
   - 同じ名前の AVD がすでにある場合は、`import-avd.bat -Force` のように `-Force` を付けます。
4. 表示された「必要なシステムイメージ」が、手順 2 で入れたものと一致しているか確認します。
5. エミュレーターを起動します（`..\restart-emulator.bat`）。

AVD は空の状態で作られるので、アプリとテスト用のデータを入れ直します。次の順に実行します。

1. `..\install-app.bat`（アプリの導入）
2. `..\push-test-files.bat`（テスト用ファイルの配置）

## 注意

- `config.ini` の `skin.path=C:\Android\skins\pixel_6` は移動元の PC の絶対パスです。移動先にこのフォルダがない場合は、エミュレーターの枠（スキン）が表示されないことがあります。その場合は `config.ini` の該当行を移動先の場所に直すか、行を削除します。
- `import-avd.ps1` は `Pixel_6.ini` の `path=` を移動先の場所に書き換えます。
- `userdata` と `snapshots` は移していないので、移動元のアプリや SMS の状態は引き継がれません。
