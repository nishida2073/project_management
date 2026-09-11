# import-macros

## 概要

`.bas`ファイルの内容を、対象のExcelマクロブック（`.xlsm`）のVBAプロジェクトへ書き込むツールです。VBEにコピペする代わりに使えます。

このフォルダ（`マクロの設定`）は、対象の`.xlsm`や`macros`フォルダが置かれているフォルダの**1つ下の階層**にあります。

## 構成

- `import-macros.bat` — 実行用のラッパー（中身は英数字のみ）
- `import-macros.ps1` — 実際の処理を行うPowerShellスクリプト
- `../macros/` — `.bas`ファイルを置くサブフォルダ（1つ上の階層。`import-macros.bat`は既定でここを`-MacroDir`として渡します）
- `backup/` — 実行のたびに作られる、対象`.xlsm`のバックアップを置くサブフォルダ（`import-macros.bat`は既定でここを`-BackupDir`として渡します）


## 基本的な使い方

### 事前準備（初回のみ）

Excelで以下を有効にしてください。

`ファイル > オプション > セキュリティセンター > セキュリティセンターの設定 > マクロの設定 > 「VBAプロジェクトオブジェクトモデルへのアクセスを信頼する」にチェック`

これが無効だと、VBAプロジェクトへアクセスできずエラーになります。

### 実行方法

```bat
import-macros.bat
```

既定では、

- `.xlsm`は1つ上のフォルダ（`import-macros.bat`が`-XlsmDir`として渡します）から探します
- `.bas`ファイルは1つ上の`macros`フォルダ（`import-macros.bat`が`-MacroDir`として渡します）から探します
- バックアップは自分のフォルダ内の`backup`サブフォルダ（`import-macros.bat`が`-BackupDir`として渡します）に作られます。フォルダが無ければ自動的に作成されます

`-XlsmDir`で指定したフォルダ内にある`.xlsm`を**すべて**処理します（1つずつ順番に開いて上書き保存）。対応する`<xlsm名>_ThisWorkbook.bas`／`<xlsm名>_<モジュール名>.bas`のペアが`-MacroDir`に無い`.xlsm`は、エラーにはならず単にスキップされます。

対応する`.bas`ペアが見つかり、実際に上書きする`.xlsm`だけ、開く前に`-BackupDir`へタイムスタンプ付きのファイル名（例：`原価管理シート_20260911-190530.xlsm`）でバックアップされます（自動削除はしないため、実行するたびに増えていきます）。

`.bas`ファイルを別のフォルダに置きたい場合は`-MacroDir`で上書きできます。

```bat
import-macros.bat -MacroDir "C:\path\to\macro-folder"
```

対象の`.xlsm`が別のフォルダにある場合は`-XlsmDir`で、そのフォルダを指定します（フォルダ内の`.xlsm`をすべて処理対象にします。ファイルを1つだけ直接指定する形ではありません）。

```bat
import-macros.bat -XlsmDir "C:\path\to\xlsm-folder"
```

※`import-macros.bat`は既定で`-MacroDir`・`-XlsmDir`・`-BackupDir`を固定して渡すため、`.bat`経由でこれらをさらに指定するとエラーになります。変えたい場合は`import-macros.ps1`を直接呼び出してください。
