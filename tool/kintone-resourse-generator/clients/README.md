# set-env.bat・set-kintone.bat の書き方

各エントリーポイントの`.bat`（`download-kintone-resources.bat`など）が実行時に`call clients\set-env.bat`
で読み込む、環境変数の既定値ファイルを置くフォルダ。

## `set-env.bat`

ローカルのフォルダパス（どの環境でも意味が変わらない、共通の設定）の既定値をまとめて設定するファイル。GUI版（`kintoneリソース生成ツール.exe`）の「設定」タブから編集できる（テキストボックスとフォルダ参照ボタンが並ぶ画面。「保存」で書き込み、「再読込」で保存前の変更を取り消せる）。テキストエディタで直接編集してもよい。

- 各行は`if not defined VAR set "VAR=値"`の形式。すでに環境変数が定義されている場合（`.bat`を呼び出す前に手動で設定していた場合など）はそちらが優先され、この行の値では上書きされない。
- GUIの「保存」はこの`if not defined VAR set "VAR=値"`という行の形を解析して値だけを書き換えるので、手動編集する場合もこの形式を崩さないこと。
- ファイル先頭で`%~dp0..`（このファイルがあるフォルダの1つ上）から`BASE_PATH`を計算しており、各既定値のフォルダパスは`%BASE_PATH%`を使った相対指定になっている。

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `COMMON_DOWNLOAD_PATH` | ダウンロード先フォルダ（`<スペース識別名>_download.xlsx`の出力先） | `download`フォルダ |
| `COMMON_CONFIG_PATH` | 設定ファイル（`<スペース識別名>_config.xlsx`）のフォルダ | `config`フォルダ |
| `COMMON_TEMPLATE_PATH` | 設定テンプレート（`.xlsx`）のフォルダ。ここに置いたファイル名（拡張子抜き）がGUIの「設定テンプレート名」ドロップダウンに並ぶ | `template`フォルダ |
| `COMMON_CHECK_OUTPUT_PATH` | データチェック結果（`<スペース識別名>_check.xlsx`）の出力先フォルダ | `checked`フォルダ |
| `COMMON_LOG_PATH` | 各工程のログの出力先フォルダ | `log`フォルダ |

末尾で、同じフォルダに`set-kintone.bat`が存在すれば呼び出す（`if exist ... call ...`）。存在しなくてもエラーにはならない。

## `set-kintone.bat`

kintoneへの接続情報（どのkintone環境に、どのユーザーで繋ぐか）を設定するファイル。`set-env.bat`のフォルダパスと違い、接続先の環境によって値が変わるものなので、あえて別ファイルに分けている。

| 変数名 | 説明 |
|---|---|
| `KINTONE_BASE_URL` | kintoneのサイトURL |
| `KINTONE_LOGIN` | kintoneへのログイン名（メールアドレス） |
| `KINTONE_PASSWORD` | kintoneへのログインパスワード |

- `set-env.bat`と同じ`if not defined VAR set "VAR=値"`の形式で、この3変数だけを書く。
- GUI版（`kintoneリソース生成ツール.exe`）の「設定」タブの「kintoneの接続情報」欄からも編集できる（パスワードは入力時に非表示になる）。「保存」を押すとこのファイルが無ければ新規作成される。テキストエディタで直接編集してもよい。
- `KINTONE_LOGIN`/`KINTONE_PASSWORD`が無い場合、または未設定の場合、`.ps1`は実際にkintone APIを呼び出す最初のタイミングでコンソールにログイン名・パスワードの入力を求める（`scripts\common.ps1`の`Get-KintoneAuthorizationHeader`）。この入力待ちは`.bat`をコマンドプロンプトから直接実行した場合だけ機能する。**GUI版はコンソールを持たず、ログ欄も入力を受け付けないため、この入力待ちには応答できず処理が進まなくなる。** GUI版を使う場合は、必ず事前に（GUIの「設定」タブ、またはこのファイルへの直接編集で）ログイン情報を設定しておくこと。

## 注意点

> `set-env.bat`自身が`%~dp0..`（自分の場所の1つ上）から`BASE_PATH`を計算しているため、`clients`フォルダを移動する場合は、その1つ上がツールのルートになるように置くこと。

> `set-env.bat`・`set-kintone.bat`の各行を`if not defined VAR set "VAR=値"`以外の形式（例：無条件の`set`）に変えると、GUIの「設定」タブが値を正しく読み書きできなくなる。
