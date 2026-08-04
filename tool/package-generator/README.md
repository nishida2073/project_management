# 個社別ZIP生成ツール

## 概要

`config\package_definition.xlsx` の内容に従って、シートごとにファイルを集めてZIP化するツール。
Excelの書き方は[config\README.md](config/README.md)を参照。

## 実行方法

`CreatePackage.bat` をダブルクリックして実行する。

処理の流れ：

```
CreatePackage.bat
  → SetEnv.bat を呼び出し、環境変数の初期値をセット
  → GeneratePackage.ps1 を実行
      - config\package_definition.xlsx を読み込み
      - シートごとにファイルをコピー・ZIP化
      - output フォルダに zip、log フォルダに log を出力
```

## 環境変数（SetEnv.bat で設定）

パス関連の設定は `SetEnv.bat` にまとめてある。PowerShellスクリプト（`GeneratePackage.ps1`）を直接編集せずに、`SetEnv.bat` の内容を書き換えるか、実行前に環境変数を設定することで変更できる。

| 変数名 | 説明 | デフォルト |
|---|---|---|
| `PKG_CONFIG_PATH` | `package_definition.xlsx` のパス | `config\package_definition.xlsx` |
| `PKG_WORK_PATH` | コピー作業用の一時フォルダ（実行時に毎回削除→再作成される） | `work` フォルダ |
| `PKG_OUTPUT_PATH` | zip の出力先フォルダ | `output` フォルダ |
| `PKG_LOG_PATH` | log の出力先フォルダ | `log` フォルダ |
| `PKG_SOURCE_BASE` | Excelの「取得元（フルパス）」列を相対パスで書いたときの共通の親フォルダ（※ドライブ文字や`\\`から始まるフルパスの行には影響しない） | このツール自体のフォルダ |
| `PKG_SHEETS_INCLUDE` | 処理対象にするシート名（カンマ区切り、複数指定可）。設定時はここに書いたシートのみ処理する | 空（絞り込みなし＝全シート対象） |
| `PKG_SHEETS_EXCLUDE` | 処理対象から除外するシート名（カンマ区切り、複数指定可） | 空（除外なし） |

すでに環境変数が設定されている場合はそれが優先され、`SetEnv.bat` の値は上書きしない（`if not defined` 方式）。

`PKG_SHEETS_INCLUDE` / `PKG_SHEETS_EXCLUDE` は `CreatePackage.bat` の引数でも指定できる（環境変数より優先される）。

```
CreatePackage.bat "include=対象シート1,対象シート2"
CreatePackage.bat "exclude=除外シート1,除外シート2"
CreatePackage.bat "include=対象シート1" "exclude=除外シート1"
```

`include=` / `exclude=` は順不同で、どちらか片方だけの指定もできる。両方指定した場合は、対象シートに絞り込んだ後にさらに除外シートを取り除く。

## 出力ファイル

シートごとに、ZIPと処理ログを別フォルダに出力する。

| ファイル | 出力先 | 内容 |
|---|---|---|
| `<シート名>.zip` | `output` フォルダ | コピーしたファイル一式をまとめたZIP |
| `<シート名>.log` | `log` フォルダ | 処理内容のログ（下記） |

```
# コピー結果
  実際にコピーした「元パス -> 先パス」の一覧

# 最終結果
  ZIPに実際に含まれる最終的なフォルダ構成（ツリー表示）
```

ログを`output`と分けているのは、`output`が納品用ZIPの置き場所であり、
内部確認用のログを誤って一緒に配布しないようにするため。

対象ファイルが1件も無かったシートは、ZIP/ログとも出力されない。

## 必要なもの

PowerShellモジュール「ImportExcel」が必要。未インストールの場合、実行時に自動でインストールされる（初回はインターネット接続とインストール確認が必要）。
