Option Explicit

Private Const MAIN_SHEET_NAME As String = "計画算定シート"

' 保存前に累積された「本当の元の値・元のフォント色」（行番号 → Array(元値の配列, 元色の配列)）。
' 行ごとに最初に触られた時点の状態を保持し続け、保存時にクリアする
Private gUndoBackupRows As Object

' 「元に戻す」用の履歴（スタック）。各要素はgUndoBackupRowsのスナップショット（Dictionary）
Private gUndoHistory As Collection

' 実績反映で変更のあった行の元値・新値（行番号 → Array(元値の配列, 新値の配列)）
Private gToggleValuesByRow As Object

' 前回保存時点（＝直近のHandleBeforeSave完了時、なければファイルを開いた時点）の
' 貼付範囲全行の値・フォント色（行番号 → Array(値の配列, 色の配列)）。
' 保存のたびにこの内容と現在のシートを比較し、差分があれば（実績反映・手動編集を問わず）履歴に積む
Private gLastSavedSnapshot As Object

' 前回チェック時点の計画算定シート最終行（行の追加・削除を検知するため）
Private gLastKnownMainLastRow As Long
Private gLastKnownMainLastRowValid As Boolean

' システム用シート「項目マッピング」表のキャッシュ（項目名 → Array(実績シート値, 計算算定シート値)）。
' 呼ぶたびにシートを走査し直さないよう、初回だけ読み込んで使い回す
Private gItemMap As Object

' システム用シート「データマッピング-区分1」「データマッピング-区分2」表のキャッシュ（区分名 → Dictionary(実績シート値 → 計算算定シート値)）。
' 呼ぶたびにシートを走査し直さないよう、初回だけ読み込んで使い回す
Private gDataMaps As Object

' Trueの場合、実績反映（対話実行）時に反映月の範囲を指定するダイアログを表示する。Falseの場合は常に全期間を反映する
' 環境変数USE_MONTH_RANGE_DIALOGから読み込む（"TRUE"または"1"でTrue、それ以外はFalse）
Function ShouldUseMonthRangeDialog() As Boolean
    Dim envVal As String
    envVal = Environ$("USE_MONTH_RANGE_DIALOG")
    ShouldUseMonthRangeDialog = (UCase$(Trim$(envVal)) = "TRUE" Or Trim$(envVal) = "1")
End Function

Sub CloseThisSheet()
    Dim currentSheet As Worksheet
    Set currentSheet = ActiveSheet

    If currentSheet.Name <> "Index" Then
        currentSheet.Visible = xlSheetHidden
        Sheets("個人計画Index").Activate
    End If
End Sub

' ============================
' Workbook_Openの本体処理
' ============================
Sub HandleWorkbookOpen()

    Dim isBrowser As Boolean
    isBrowser = (Application.OperatingSystem = "")

    If isBrowser Then Exit Sub

    EnsureButtonsExist

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets(MAIN_SHEET_NAME)

    ' 開いた時点の状態を、保存時の差分比較の基準として記録しておく
    Dim mapMainCol As Object, mapMainRange As Object
    Set mapMainCol = GetMainColMap()
    Set mapMainRange = GetMainRangeMap()
    Set gLastSavedSnapshot = BuildFullSheetSnapshot(wsMain, mapMainCol, mapMainRange)

    ' 行の追加・削除検知の基準も、開いた時点の行数にしておく
    gLastKnownMainLastRow = wsMain.Cells(wsMain.Rows.Count, mapMainCol("年度")).End(xlUp).Row
    gLastKnownMainLastRowValid = True

    If wsMain.Visible = xlSheetVisible Then
        wsMain.Activate
        wsMain.Range("A1").Select
    End If

End Sub


' ============================
' Workbook_BeforeSaveの本体処理（反映・ハイライトで色を付けたセルを元の色へ戻す）
' ============================
Sub HandleBeforeSave()

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets(MAIN_SHEET_NAME)
    Dim mapMainCol As Object
    Dim mapMainRange As Object

    Set mapMainCol = GetMainColMap()
    Set mapMainRange = GetMainRangeMap()

    ' 前回チェック時から行の追加・削除がないか確認し、あれば履歴・ハイライトの記録を破棄する
    CheckRowCountAndResetIfChanged ws, mapMainCol, mapMainRange

    ' ここから先はセル単位でFont.Colorを書き換えるため、1件ごとの再描画を止めておく
    Application.ScreenUpdating = False

    ' 保存時の差分チェックで除外する「実績反映で触った行」の集合
    Dim touchedRows As Object
    Set touchedRows = gUndoBackupRows
    If touchedRows Is Nothing Then Set touchedRows = CreateObject("Scripting.Dictionary")

    ' 実績反映・実績なしグレー化した行は、値はそのままに元のフォント色へ戻す
    Dim key As Variant
    For Each key In touchedRows.Keys
        Dim foundRow As Long
        foundRow = key

        Dim rng As Range
        Set rng = ws.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)

        Dim backupData As Variant
        backupData = touchedRows(key)
        SetFontColors rng, backupData(1)   ' (0)=元の値, (1)=元のフォント色。値には触れない
    Next key
    Set gUndoBackupRows = CreateObject("Scripting.Dictionary")

    ' 重複行ハイライトも、自動色へ戻す
    Dim lastRowForDupReset As Long
    lastRowForDupReset = ws.Cells(ws.Rows.Count, mapMainCol("年度")).End(xlUp).Row
    ResetDupHighlightColumns ws, mapMainCol, lastRowForDupReset

    ' 前回保存時点からの状態(gLastSavedSnapshot)を、実績反映で触った行を除いて現在の状態と比較し、
    ' 変化があれば（＝手動でのセル編集があれば）履歴に積む
    Dim currentSnapshot As Object
    Set currentSnapshot = BuildFullSheetSnapshot(ws, mapMainCol, mapMainRange)

    PushSaveCheckpoint gLastSavedSnapshot, currentSnapshot, touchedRows
    Set gLastSavedSnapshot = currentSnapshot

    Set gToggleValuesByRow = CreateObject("Scripting.Dictionary")

    Application.ScreenUpdating = True

End Sub


' ============================
' 貼付範囲の全行（行番号 → Array(値の配列, フォント色の配列)）のスナップショットを作る
' （実績反映・手動編集を問わず、保存時点でのシート全体の状態を比較するために使う）
' ============================
Function BuildFullSheetSnapshot(ws As Worksheet, mapMainCol As Object, mapMainRange As Object) As Object
    Dim snap As Object
    Set snap = CreateObject("Scripting.Dictionary")

    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, mapMainCol("年度")).End(xlUp).Row

    Dim dataStartRow As Long
    dataStartRow = GetMainDataStartRow()

    If lastRow >= dataStartRow Then
        Dim r As Long
        For r = dataStartRow To lastRow
            Dim rng As Range
            Set rng = ws.Range(mapMainRange("開始") & r & ":" & mapMainRange("終了") & r)
            snap(r) = Array(rng.Value, GetFontColors(rng))
        Next r
    End If

    Set BuildFullSheetSnapshot = snap
End Function


' ============================
' 計画算定シートの最終行が前回チェック時から変わっていないか確認する。
' 行の追加・削除があると、行番号をキーにしている「元に戻す」履歴やハイライト情報が
' 別の行を指してしまい危険なため、変化を検知した場合は安全側に倒してすべて破棄する
' ============================
Sub CheckRowCountAndResetIfChanged(ws As Worksheet, mapMainCol As Object, mapMainRange As Object)
    Dim currentLastRow As Long
    currentLastRow = ws.Cells(ws.Rows.Count, mapMainCol("年度")).End(xlUp).Row

    If gLastKnownMainLastRowValid Then
        If currentLastRow <> gLastKnownMainLastRow Then
            ClearAllUndoState ws, mapMainCol, mapMainRange
        End If
    End If

    gLastKnownMainLastRow = currentLastRow
    gLastKnownMainLastRowValid = True
End Sub


' ============================
' 「元に戻す」履歴・ハイライトに関する記録をすべて破棄し、現在のシート状態を新しい基準にする
' ============================
Sub ClearAllUndoState(ws As Worksheet, mapMainCol As Object, mapMainRange As Object)
    Set gUndoBackupRows = CreateObject("Scripting.Dictionary")
    Set gUndoHistory = New Collection
    Set gToggleValuesByRow = CreateObject("Scripting.Dictionary")

    ' 行番号が信頼できなくなったため、個々の行の「元の色」には戻せない。
    ' 代わりに、ハイライト対象になり得る列を貼付範囲・重複チェック列とも一括で自動色に戻す
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, mapMainCol("年度")).End(xlUp).Row

    Dim dataStartRow As Long
    dataStartRow = GetMainDataStartRow()

    If lastRow >= dataStartRow Then
        ws.Range(mapMainRange("開始") & dataStartRow & ":" & mapMainRange("終了") & lastRow).Font.ColorIndex = xlAutomatic
    End If

    ResetDupHighlightColumns ws, mapMainCol, lastRow

    Set gLastSavedSnapshot = BuildFullSheetSnapshot(ws, mapMainCol, mapMainRange)
End Sub


' ============================
' 計画算定シートに実績反映・元に戻すボタンが無ければ作成する。
' Workbook_Open、および Workbook_BeforeClose がボタン削除後に予約する
' 復元チェック（Application.OnTimeの呼び出し先は標準モジュールである必要があるため、ここに置く）
' の両方から呼ばれる
' ============================
Sub EnsureButtonsExist()

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets(MAIN_SHEET_NAME)

    If wsMain.Visible <> xlSheetVisible Then Exit Sub

    CreateButton wsMain, "MacroProcButton999", "D2", "実績反映", "ImportFromOtherBook"
    CreateButton wsMain, "UndoProcButton999", "E2", "元に戻す", "UndoLastCheckpoint"

End Sub


' ============================
' フォームコントロールのボタンを作成し、指定セルの左上に配置してマクロを割り当てる
' ============================
Sub CreateButton(wsMain As Worksheet, buttonName As String, targetCellAddress As String, caption As String, macroName As String)

    ' 同名の図形が既に残っている場合は先に削除しておく（名前の衝突を防ぐ）
    DeleteButtonIfExists wsMain, buttonName

    Dim targetCell As Range
    Set targetCell = wsMain.Range(targetCellAddress)

    Dim btn As Button
    Set btn = wsMain.Buttons.Add(targetCell.Left, targetCell.Top, 60, 20)

    btn.Name = buttonName
    btn.Caption = caption
    btn.OnAction = macroName
    btn.Placement = xlMove   ' セルと一緒に移動はするが、列幅・行高を変えてもサイズは変えない

    With btn.Characters.Font
        .Name = "Meiryo UI"
        .Size = 9
        .Bold = True
    End With

End Sub


' ============================
' Workbook_BeforeCloseの本体処理（ボタン削除＋復元チェックの予約）
' ============================
Sub HandleBeforeClose()

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets(MAIN_SHEET_NAME)

    DeleteButtonIfExists wsMain, "MacroProcButton999"
    DeleteButtonIfExists wsMain, "UndoProcButton999"

    ' このあと「変更を保存しますか？」でキャンセルされ、閉じずに残る場合に備えて
    ' 少し後にボタンが残っているか確認・復元する処理を予約しておく
    Application.OnTime Now, "'" & ThisWorkbook.Name & "'!EnsureButtonsExist"

End Sub


' ============================
' 指定名のボタンがシート上に存在すれば削除する
' ============================
Sub DeleteButtonIfExists(ws As Worksheet, buttonName As String)

    Dim shp As Shape
    On Error Resume Next
    Set shp = ws.Shapes(buttonName)
    On Error GoTo 0

    If Not shp Is Nothing Then
        shp.Delete
    End If

End Sub

' ============================
' 実績Excelを読み込んで実績を反映する
' ============================
Function ImportFromOtherBook(Optional otherFilePath As Variant) As String

    Dim isInteractive As Boolean
    isInteractive = IsMissing(otherFilePath)

    ' ブック・シート
    Dim wbOther As Workbook
    Dim wsOther As Worksheet
    Dim wsMain As Worksheet
    Dim otherFilePathToOpen As Variant

    ' マッピング（列位置・貼付範囲・データ開始行）
    Dim mapMainCol As Object
    Dim mapMainRange As Object
    Dim mapOtherCol As Object
    Dim mapOtherRange As Object
    Dim otherDataStartRow As Long

    ' 行番号
    Dim lastRowMain As Long
    Dim lastRowOther As Long
    Dim otherRow As Long
    Dim foundRow As Long

    ' 照合キー
    Dim mainIndex As Object
    Dim keyItems As Variant
    Dim otherKeyVals() As Variant
    Dim ki As Long
    Dim idxKey As String
    Dim matchedRows As Object

    ' 反映処理（値・色の書き換え）
    Dim mainRange As Range, otherRange As Range
    Dim oldVals As Variant, newVals As Variant
    Dim completed As Boolean

    ' 集計（件数）
    Dim reflectedCount As Long           ' 反映件数
    Dim skipJissekiOnlyCount As Long     ' スキップ件数（実績）：実績シートにはあるが計画算定シートにない
    Dim skipKeikakuOnlyCount As Long     ' スキップ件数（計画）：計画算定シートにはあるが実績シートにない
    Dim skipDupCount As Long             ' スキップ件数（実績重複）

    ' 集計（行番号一覧）
    Dim reflectedRows As String          ' 反映した「実績行→計画行」の一覧
    Dim skipJissekiOnlyRows As String    ' スキップ（実績）の実績シート側行番号の一覧
    Dim skipKeikakuOnlyRows As String    ' スキップ（計画）の計画算定シート側行番号の一覧
    Dim skipDupRows As String            ' スキップ（実績重複）の実績シート側行番号の一覧

    ' 反映月の範囲
    Dim startPos As Long, endPos As Long

    ' ここ以降のエラーは全て CleanFail で拾う
    On Error GoTo CleanFail

    Set wsMain = ThisWorkbook.Sheets(MAIN_SHEET_NAME)
    Set mapMainCol = GetMainColMap()
    Set mapMainRange = GetMainRangeMap()

    ' 重複チェックの色付けはセル単位のFont.Color操作を大量に行うため、
    ' 画面再描画をここから止めておく（止め忘れるとチェックのたびに1件ずつ描画されて非常に遅くなる）
    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    Application.EnableEvents = False

    ' === ① 前回チェック時から行の追加・削除がないか確認し、あれば履歴・ハイライトの記録を破棄する ===
    CheckRowCountAndResetIfChanged wsMain, mapMainCol, mapMainRange

    ' === ② 対象ファイルを選ぶ前に、計画算定シート側の重複チェックを行う ===
    lastRowMain = wsMain.Cells(wsMain.Rows.Count, mapMainCol("年度")).End(xlUp).Row
    CheckDuplicateRows wsMain, mapMainCol, lastRowMain

    ' 重複が無くなっていれば、直前の重複ハイライト解除がここで既に反映されているはず。
    ' ファイル選択・月範囲ダイアログより前に画面を更新し、消えたことをすぐ見えるようにする
    Application.ScreenUpdating = True

    ' === ③ 対話実行はファイルダイアログ、バッチ実行は引数のパスを使う ===
    If isInteractive Then
        otherFilePathToOpen = Application.GetOpenFilename("Excelファイル (*.xlsx), *.xlsx")
        If otherFilePathToOpen = False Then GoTo CleanExit
    Else
        otherFilePathToOpen = otherFilePath
    End If

    ' === ④ Otherブックを開く ===
    Set wbOther = Workbooks.Open(otherFilePathToOpen, ReadOnly:=True)

    If Not SheetExists(wbOther, "実績") Then
        ImportFromOtherBook = "選択したファイルに「実績」シートが見つかりません。" & vbCrLf & _
               "ファイルが正しいか確認してください。" & vbCrLf & "対象ファイル: " & otherFilePathToOpen
        If isInteractive Then MsgBox ImportFromOtherBook, vbExclamation
        GoTo CleanExit
    End If

    ' === ④' 対話実行時のみ、反映する月の範囲を聞く（バッチ実行時は全期間） ===
    If isInteractive And ShouldUseMonthRangeDialog() Then
        Dim monthRangeInput As Variant
        Dim monthRangeStr As String
        Dim rangeParts() As String
        Dim startMonthStr As String, endMonthStr As String
        Dim startMonth As Long, endMonth As Long
        Dim isValidRange As Boolean
        isValidRange = False

        Do While Not isValidRange
            monthRangeInput = Application.InputBox("反映する月の範囲を「開始月～終了月」の形式で入力してください（例：4～9）", "反映月の指定", "4～3", Type:=2)
            If VarType(monthRangeInput) = vbBoolean Then
                ' キャンセルされた場合は実績反映そのものを中止する
                GoTo CleanExit
            End If

            monthRangeStr = CStr(monthRangeInput)
            If monthRangeStr = "" Then monthRangeStr = "4～3"   ' 空欄でOKした場合は全期間として扱う

            rangeParts = Split(monthRangeStr, "～")
            If UBound(rangeParts) <> 1 Then
                MsgBox "月の範囲は「開始月～終了月」の形式（例：4～9）で入力してください。", vbExclamation
                GoTo RetryMonthRange
            End If

            startMonthStr = Trim(rangeParts(0))
            endMonthStr = Trim(rangeParts(1))
            If startMonthStr = "" Then startMonthStr = "4"   ' 開始月省略時は4月扱い
            If endMonthStr = "" Then endMonthStr = "3"       ' 終了月省略時は3月扱い

            If Not IsNumeric(startMonthStr) Or Not IsNumeric(endMonthStr) Then
                MsgBox "月の範囲は「開始月～終了月」の形式（例：4～9）で入力してください。", vbExclamation
                GoTo RetryMonthRange
            End If

            startMonth = CLng(startMonthStr)
            endMonth = CLng(endMonthStr)
            If startMonth < 1 Or startMonth > 12 Or endMonth < 1 Or endMonth > 12 Then
                MsgBox "開始月・終了月は1～12の範囲で入力してください。", vbExclamation
                GoTo RetryMonthRange
            End If

            startPos = FiscalMonthPosition(startMonth)
            endPos = FiscalMonthPosition(endMonth)
            If startPos > endPos Then
                MsgBox "開始月は終了月と同じか、それより前（4月始まりの年度内）にしてください。", vbExclamation
                GoTo RetryMonthRange
            End If

            isValidRange = True
RetryMonthRange:
        Loop
    Else
        startPos = 1
        endPos = 12
    End If

    Set wsOther = wbOther.Sheets("実績")   ' ←読み込み元

    ' === ⑤ マッピングは1回だけ読み込む（mapMainRangeは冒頭で読み込み済み） ===
    Set mapOtherCol = GetOtherColMap()
    Set mapOtherRange = GetOtherRangeMap()
    otherDataStartRow = GetOtherDataStartRow()

    ' ここから先も再びセル単位でFont.Colorを書き換えるため、画面更新を止め直す
    Application.ScreenUpdating = False

    ' 前回までの実行で触った行は、一旦「本当の元の色」に戻しておく（値には触れない）
    If Not gUndoBackupRows Is Nothing Then
        Dim resetKey As Variant
        For Each resetKey In gUndoBackupRows.Keys
            Dim resetRow As Long
            resetRow = resetKey
            Dim resetRng As Range
            Set resetRng = wsMain.Range(mapMainRange("開始") & resetRow & ":" & mapMainRange("終了") & resetRow)
            Dim resetBackup As Variant
            resetBackup = gUndoBackupRows(resetKey)
            SetFontColors resetRng, resetBackup(1)
        Next resetKey
    End If

    ' 保存されるまでの「本当の元の値・元の色」は行ごとに最初に触られたときのみ記録し、
    ' 以降の実行をまたいで保持し続ける（ハイライト・トグルの比較基準として使うため）
    If gUndoBackupRows Is Nothing Then Set gUndoBackupRows = CreateObject("Scripting.Dictionary")
    If gToggleValuesByRow Is Nothing Then Set gToggleValuesByRow = CreateObject("Scripting.Dictionary")
    Set matchedRows = CreateObject("Scripting.Dictionary")

    ' 今回の実行だけを元に戻すための履歴用スナップショット（行番号 → Array(実行前の値, 実行前の色)）
    Dim stepSnapshot As Object
    Set stepSnapshot = CreateObject("Scripting.Dictionary")

    ' === ⑥ Otherの可変範囲の最終行を取得し、キー項目（年度・案件ID・区分1・区分2）の
    ' 列を一括で配列に読み込む ===
    lastRowOther = wsOther.Cells(wsOther.Rows.Count, mapOtherCol("年度")).End(xlUp).Row

    keyItems = KeyItemNames()
    ReDim otherKeyVals(LBound(keyItems) To UBound(keyItems))

    If lastRowOther >= otherDataStartRow Then
        For ki = LBound(keyItems) To UBound(keyItems)
            Dim otherCol As Variant
            otherCol = mapOtherCol(keyItems(ki))
            otherKeyVals(ki) = wsOther.Range(wsOther.Cells(1, otherCol), wsOther.Cells(lastRowOther, otherCol)).Value
        Next ki
    End If

    ' 実績反映時の行検索用に、計画算定シート側の索引を作る
    Set mainIndex = BuildMainIndex(wsMain, mapMainCol, lastRowMain)

    ' === ⑦ 行ループ（キーの判定は配列上で行い、一致した行だけシートへアクセスする） ===
    For otherRow = otherDataStartRow To lastRowOther

        ' キー項目ごとに、gDataMapsに同名の変換表があれば変換した値を、
        ' 無ければ生の値（年度のみ日付/数値からの正規化）をそのままキーに使う
        Dim allMatched As Boolean
        allMatched = True

        Dim keyParts() As String
        ReDim keyParts(LBound(keyItems) To UBound(keyItems))

        For ki = LBound(keyItems) To UBound(keyItems)
            Dim keyItemName As String
            keyItemName = keyItems(ki)

            Dim rawVal As Variant
            rawVal = otherKeyVals(ki)(otherRow, 1)

            If keyItemName = "年度" Then
                keyParts(ki) = CStr(NormalizeYear(rawVal))
            ElseIf gDataMaps.Exists(keyItemName) Then
                Dim rawText As String
                rawText = Trim(CStr(rawVal))
                If gDataMaps(keyItemName).Exists(rawText) Then
                    keyParts(ki) = gDataMaps(keyItemName)(rawText)
                Else
                    allMatched = False
                    Exit For
                End If
            Else
                keyParts(ki) = Trim(rawVal & "")
            End If
        Next ki

        If allMatched Then
            idxKey = Join(keyParts, "|")

            ' === ⑧ Dictionaryで一致する行を即座に取得 ===
            If mainIndex.Exists(idxKey) Then
                foundRow = mainIndex(idxKey)

                ' 実績シート側に重複行があり、同じ行へ既に反映済みの場合は再処理しない
                ' （2回目以降の処理が「1回目で上書きした後の値」を元に比較してしまい、
                '   正しく付いた赤色やUndo用バックアップが誤って上書きされるため）
                If Not matchedRows.Exists(foundRow) Then
                    matchedRows(foundRow) = True

                    ' === ⑨ 一致した行に貼り付け（値が変わったセルだけ赤色にする） ===
                    Set mainRange = wsMain.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)
                    Set otherRange = wsOther.Range(mapOtherRange("開始") & otherRow & ":" & mapOtherRange("終了") & otherRow)

                    Dim currentColors As Variant
                    currentColors = GetFontColors(mainRange)   ' 今回の実行開始時点のフォント色

                    Dim otherVals As Variant
                    otherVals = otherRange.Value

                    Dim currentVals As Variant
                    currentVals = mainRange.Value       ' 今回の実行開始時点の値（合成のベースにする）

                    ' 今回の実行だけを元に戻すための情報
                    stepSnapshot(foundRow) = Array(currentVals, currentColors)

                    ' 「本当の元の値・元の色」は最初に触られたときだけ記録する
                    If Not gUndoBackupRows.Exists(foundRow) Then
                        gUndoBackupRows(foundRow) = Array(currentVals, currentColors)
                    End If

                    oldVals = gUndoBackupRows(foundRow)(0)   ' ハイライト・トグル比較用の「本当の元の値」

                    ' 1列目（過年度）は常に反映し、2列目以降（4月～翌3月）は指定範囲の月だけ反映する
                    Dim mergedVals As Variant
                    mergedVals = currentVals
                    Dim colOffset As Long
                    For colOffset = 1 To mainRange.Cells.Count
                        If colOffset = 1 Or ((colOffset - 1) >= startPos And (colOffset - 1) <= endPos) Then
                            mergedVals(1, colOffset) = otherVals(1, colOffset)
                        End If
                    Next colOffset

                    mainRange.Value = mergedVals
                    newVals = mainRange.Value

                    gToggleValuesByRow(foundRow) = Array(oldVals, newVals)

                    HighlightChangedCells mainRange, oldVals, newVals

                    reflectedCount = reflectedCount + 1
                    reflectedRows = AppendItem(reflectedRows, otherRow & "→" & foundRow)
                Else
                    skipDupCount = skipDupCount + 1
                    skipDupRows = AppendItem(skipDupRows, CStr(otherRow))
                End If
            Else
                skipJissekiOnlyCount = skipJissekiOnlyCount + 1
                skipJissekiOnlyRows = AppendItem(skipJissekiOnlyRows, CStr(otherRow))
            End If

        Else
            skipJissekiOnlyCount = skipJissekiOnlyCount + 1
            skipJissekiOnlyRows = AppendItem(skipJissekiOnlyRows, CStr(otherRow))
        End If

    Next otherRow

    ' === ⑩ 一度もマッチしなかった「予実=実績」行をグレー表示にする ===
    MarkUnmatchedActualRows wsMain, mapMainCol, mapMainRange, matchedRows, gUndoBackupRows, stepSnapshot, lastRowMain, skipKeikakuOnlyCount, skipKeikakuOnlyRows

    ' 今回の実行分を「元に戻す」用の履歴に積む（直前と内容が同じなら追加しない）
    PushUndoHistory stepSnapshot

    completed = True

CleanExit:
    Application.EnableEvents = True
    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = True

    If Not wbOther Is Nothing Then wbOther.Close SaveChanges:=False

    If completed Then
        Dim monthRangeLine As String
        If isInteractive And ShouldUseMonthRangeDialog() Then
            monthRangeLine = "反映月：" & startMonth & "月～" & endMonth & "月" & vbCrLf & vbCrLf
        Else
            monthRangeLine = ""
        End If

        ImportFromOtherBook = "実績反映が完了しました。" & vbCrLf & vbCrLf & _
               monthRangeLine & _
               "反映（実績シート→" & MAIN_SHEET_NAME & "）：" & reflectedCount & "件" & vbCrLf & _
               IIf(reflectedRows = "", "", "　" & reflectedRows & vbCrLf) & _
               "スキップ（実績シート：" & MAIN_SHEET_NAME & "にデータなし）：" & skipJissekiOnlyCount & "件" & vbCrLf & _
               IIf(skipJissekiOnlyRows = "", "", "　" & skipJissekiOnlyRows & vbCrLf) & _
               "スキップ（実績シート：データの重複）：" & skipDupCount & "件" & vbCrLf & _
               IIf(skipDupRows = "", "", "　" & skipDupRows & vbCrLf) & _
               "スキップ（計画シート：実績シートに実績なし）：" & skipKeikakuOnlyCount & "件" & _
               IIf(skipKeikakuOnlyRows = "", "", vbCrLf & "　" & skipKeikakuOnlyRows)

        If isInteractive Then MsgBox ImportFromOtherBook, vbInformation
    End If

    Exit Function

CleanFail:
    Dim errDescription As String
    errDescription = Err.Description

    If isInteractive Then
        On Error Resume Next
        ThisWorkbook.Activate
        If Not wsMain Is Nothing Then wsMain.Activate
        On Error GoTo 0

        ' 重複行の赤色ハイライトなど、ここまでの変更をエラーメッセージより先に見せる
        Application.ScreenUpdating = True
    End If

    ImportFromOtherBook = "エラーが発生しました。" & vbCrLf & errDescription
    If isInteractive Then MsgBox ImportFromOtherBook
    Resume CleanExit

End Function


' ============================
' 履歴を1段階分だけ元に戻す（「元に戻す」ボタンを押すたびに1回分ずつ遡る）
' ============================
Sub UndoLastCheckpoint()

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets(MAIN_SHEET_NAME)

    Dim mapMainCol As Object, mapMainRange As Object
    Set mapMainCol = GetMainColMap()
    Set mapMainRange = GetMainRangeMap()

    ' 前回チェック時から行の追加・削除がないか確認し、あれば履歴・ハイライトの記録を破棄する
    CheckRowCountAndResetIfChanged wsMain, mapMainCol, mapMainRange

    Dim noHistory As Boolean
    noHistory = (gUndoHistory Is Nothing)
    If Not noHistory Then noHistory = (gUndoHistory.Count = 0)

    If noHistory Then
        MsgBox "実行履歴がありません。"
        Exit Sub
    End If

    Dim snapshot As Object
    Set snapshot = gUndoHistory(gUndoHistory.Count)
    gUndoHistory.Remove gUndoHistory.Count

    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    Application.EnableEvents = False

    ApplyUndoSnapshot wsMain, mapMainRange, snapshot

    ' 元に戻した直後のシートの状態を、次回保存時の比較基準として更新しておく
    Set gLastSavedSnapshot = BuildFullSheetSnapshot(wsMain, mapMainCol, mapMainRange)

    Application.EnableEvents = True
    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = True

    MsgBox "直前の状態に戻しました。"

End Sub


' ============================
' 指定されたスナップショット（行番号 → Array(値, フォント色)）の内容をシートへ書き戻す
' ============================
Sub ApplyUndoSnapshot(ws As Worksheet, mapMainRange As Object, snapshot As Object)
    If snapshot Is Nothing Then Exit Sub

    Dim key As Variant
    For Each key In snapshot.Keys
        Dim foundRow As Long
        foundRow = key

        Dim rng As Range
        Set rng = ws.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)

        Dim snapData As Variant
        snapData = snapshot(key)

        rng.Value = snapData(0)
        SetFontColors rng, snapData(1)

        ' 元に戻した行は、ダブルクリックでの除外トグル対象からも外す
        If Not gToggleValuesByRow Is Nothing Then
            If gToggleValuesByRow.Exists(foundRow) Then gToggleValuesByRow.Remove foundRow
        End If

        ' 元に戻した行は「本当の元の値・元の色」の記録も削除する
        If Not gUndoBackupRows Is Nothing Then
            If gUndoBackupRows.Exists(foundRow) Then gUndoBackupRows.Remove foundRow
        End If
    Next key
End Sub


' ============================
' 保存時のチェックポイントを履歴に積むかどうかを判定する。
' oldSnapshot（前回保存時点）とcurrentSnapshot（現在の状態）を、excludeRows（実績反映で
' 今回触った行。別途stepSnapshotとして既に履歴に積まれている）を除いて比較し、
' 差があれば（＝手動でのセル編集や新規行の追加があれば）oldSnapshotを履歴に積む
' ============================
Sub PushSaveCheckpoint(oldSnapshot As Object, currentSnapshot As Object, excludeRows As Object)
    Dim hasChange As Boolean
    hasChange = False

    Dim rowKey As Variant
    For Each rowKey In currentSnapshot.Keys
        If Not excludeRows.Exists(rowKey) Then
            If RowSnapshotToString(oldSnapshot, rowKey) <> RowSnapshotToString(currentSnapshot, rowKey) Then
                hasChange = True
                Exit For
            End If
        End If
    Next rowKey

    If Not hasChange And Not oldSnapshot Is Nothing Then
        For Each rowKey In oldSnapshot.Keys
            If Not currentSnapshot.Exists(rowKey) And Not excludeRows.Exists(rowKey) Then
                hasChange = True
                Exit For
            End If
        Next rowKey
    End If

    If hasChange Then PushUndoHistory oldSnapshot
End Sub


' ============================
' 履歴スタック（gUndoHistory）に1件積む。直前の履歴と内容が同じ場合は追加しない
' ============================
Sub PushUndoHistory(snapshot As Object)
    If gUndoHistory Is Nothing Then Set gUndoHistory = New Collection
    If snapshot Is Nothing Then Exit Sub
    If snapshot.Count = 0 Then Exit Sub

    Dim newSig As String
    newSig = BuildUndoSignature(snapshot)

    If gUndoHistory.Count > 0 Then
        If BuildUndoSignature(gUndoHistory(gUndoHistory.Count)) = newSig Then Exit Sub
    End If

    gUndoHistory.Add CloneRowSnapshot(snapshot)
End Sub


' ============================
' 行番号→Array(値, フォント色) 形式のDictionaryを複製する
' ============================
Function CloneRowSnapshot(dic As Object) As Object
    Dim newDic As Object
    Set newDic = CreateObject("Scripting.Dictionary")

    Dim key As Variant
    For Each key In dic.Keys
        newDic(key) = dic(key)
    Next key

    Set CloneRowSnapshot = newDic
End Function


' ============================
' 行番号→Array(値, フォント色) 形式のDictionaryの内容を比較用の文字列に変換する
' （履歴の重複追加を避けるための簡易な内容比較に使う）
' ============================
Function BuildUndoSignature(dic As Object) As String
    If dic Is Nothing Then
        BuildUndoSignature = ""
        Exit Function
    End If

    Dim sig As String
    Dim key As Variant
    For Each key In dic.Keys
        sig = sig & "#" & key & ":" & RowSnapshotToString(dic, key)
    Next key

    BuildUndoSignature = sig
End Function


' ============================
' Dictionary内の1行分（Array(値, フォント色)）だけを比較用文字列に変換する。
' 該当キーが無い場合は空文字列を返す
' ============================
Function RowSnapshotToString(dic As Object, key As Variant) As String
    If dic Is Nothing Then Exit Function
    If Not dic.Exists(key) Then Exit Function

    Dim data As Variant
    data = dic(key)
    RowSnapshotToString = ValsToString(data(0)) & "/" & ColorsToString(data(1))
End Function


' ============================
' mainRange.Valueで取得した値（配列またはスカラー）を比較用文字列に変換する
' ============================
Function ValsToString(vals As Variant) As String
    Dim s As String
    If IsArray(vals) Then
        Dim i As Long
        For i = LBound(vals, 2) To UBound(vals, 2)
            s = s & CStr(vals(1, i)) & vbTab
        Next i
    Else
        s = CStr(vals)
    End If
    ValsToString = s
End Function


' ============================
' GetFontColorsで取得した色の配列を比較用文字列に変換する
' ============================
Function ColorsToString(colors As Variant) As String
    Dim s As String
    Dim i As Long
    For i = LBound(colors) To UBound(colors)
        s = s & colors(i) & vbTab
    Next i
    ColorsToString = s
End Function


' ============================
' 範囲内の各セルのフォント色を配列として取得する
' ============================
Function GetFontColors(rng As Range) As Variant
    Dim arr() As Long
    Dim i As Long

    ReDim arr(1 To rng.Cells.Count)
    For i = 1 To rng.Cells.Count
        arr(i) = rng.Cells(i).Font.Color
    Next i

    GetFontColors = arr
End Function


' ============================
' 予実=実績だが、今回の実行で一度も実績シート側とマッチしなかった行をグレー表示にする
' ============================
Sub MarkUnmatchedActualRows(ws As Worksheet, mapMainCol As Object, mapMainRange As Object, matchedRows As Object, backupRows As Object, stepSnapshot As Object, lastRow As Long, ByRef unmatchedCount As Long, ByRef unmatchedRows As String)
    unmatchedCount = 0
    unmatchedRows = ""

    Dim dataStartRow As Long
    dataStartRow = GetMainDataStartRow()

    If lastRow < dataStartRow Then Exit Sub

    Dim colYojitsu As Variant
    colYojitsu = mapMainCol("予実")

    Dim yojitsus As Variant
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value

    Dim r As Long
    For r = dataStartRow To lastRow
        If yojitsus(r, 1) = "実績" Then
            If Not matchedRows.Exists(r) Then
                Dim rng As Range
                Set rng = ws.Range(mapMainRange("開始") & r & ":" & mapMainRange("終了") & r)

                Dim beforeVals As Variant, beforeColors As Variant
                beforeVals = rng.Value
                beforeColors = GetFontColors(rng)

                ' 今回の実行だけを元に戻すための情報
                stepSnapshot(r) = Array(beforeVals, beforeColors)

                ' グレーにする前の「本当の元の値・元の色」は最初に触られたときだけ記録する
                If Not backupRows.Exists(r) Then
                    backupRows(r) = Array(beforeVals, beforeColors)
                End If

                rng.Font.Color = RGB(150, 150, 150)

                unmatchedCount = unmatchedCount + 1
                unmatchedRows = AppendItem(unmatchedRows, CStr(r))
            End If
        End If
    Next r
End Sub


' ============================
' カンマ区切りリストに項目を追加する
' ============================
Function AppendItem(list As String, item As String) As String
    If list = "" Then
        AppendItem = item
    Else
        AppendItem = list & ", " & item
    End If
End Function


' ============================
' GetFontColors で取得した配列を範囲に書き戻す
' ============================
Sub SetFontColors(rng As Range, colors As Variant)
    Dim i As Long
    For i = 1 To rng.Cells.Count
        rng.Cells(i).Font.Color = colors(i)
    Next i
End Sub


' ============================
' Main側の「年度|案件ID|区分1|区分2」→行番号 の索引を作る
' ============================
Function BuildMainIndex(ws As Worksheet, mapMainCol As Object, lastRow As Long) As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    Dim dataStartRow As Long
    dataStartRow = GetMainDataStartRow()

    If lastRow < dataStartRow Then
        Set BuildMainIndex = dic
        Exit Function
    End If

    Dim colYojitsu As Variant
    colYojitsu = mapMainCol("予実")

    Dim yojitsus As Variant
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value

    ' キー項目（年度・案件ID・区分1・区分2）それぞれの列を、計画算定シート側の値のまま一括で読み込む
    ' （計画算定シート側は既に「変換後」の表記が入っているため、gDataMapsによる変換は不要）
    Dim keyItems As Variant
    keyItems = KeyItemNames()

    Dim keyVals() As Variant
    ReDim keyVals(LBound(keyItems) To UBound(keyItems))

    Dim ki As Long
    For ki = LBound(keyItems) To UBound(keyItems)
        Dim col As Variant
        col = mapMainCol(keyItems(ki))
        keyVals(ki) = ws.Range(ws.Cells(1, col), ws.Cells(lastRow, col)).Value
    Next ki

    Dim r As Long
    For r = dataStartRow To lastRow
        If yojitsus(r, 1) = "実績" Then
            Dim allFilled As Boolean
            allFilled = True

            Dim parts() As String
            ReDim parts(LBound(keyItems) To UBound(keyItems))

            For ki = LBound(keyItems) To UBound(keyItems)
                Dim v As String
                v = Trim(keyVals(ki)(r, 1) & "")
                If v = "" Then
                    allFilled = False
                    Exit For
                End If
                parts(ki) = v
            Next ki

            If allFilled Then
                Dim idxKey As String
                idxKey = Join(parts, "|")

                If Not dic.Exists(idxKey) Then dic(idxKey) = r
            End If
        End If
    Next r

    Set BuildMainIndex = dic
End Function


' ============================
' 年度・案件ID・案件名・区分1・区分2・予実（remove-duplicate-rows.ps1と同じキー）の
' 重複チェックを行う。前回のチェックで付けた重複ハイライトは一旦元の色に戻したうえで判定し直し、
' 重複が見つかった場合は行をハイライトしたうえでエラーを発生させる
' ============================
Sub CheckDuplicateRows(ws As Worksheet, mapMainCol As Object, lastRow As Long)
    Dim colYear As Variant, colCase As Variant, colName As Variant, colKubun1 As Variant, colKubun2 As Variant, colYojitsu As Variant
    colYear = mapMainCol("年度")
    colCase = mapMainCol("案件ID")
    colName = mapMainCol("案件名")
    colKubun1 = mapMainCol("区分1")
    colKubun2 = mapMainCol("区分2")
    colYojitsu = mapMainCol("予実")

    ' 対象6列はこのチェック以外で色を付けることが無いため、判定のたびに一旦すべて
    ' 自動色に戻してから、現在も重複している行だけ塗り直す（これなら重複が解消
    ' されていれば必ず自動色に戻り、「前回の色を覚えておいて戻す」仕組みが不要）
    ResetDupHighlightColumns ws, mapMainCol, lastRow

    Dim dataStartRow As Long
    dataStartRow = GetMainDataStartRow()

    If lastRow < dataStartRow Then Exit Sub

    Dim years As Variant, caseIds As Variant, kubun1s As Variant, kubun2s As Variant, yojitsus As Variant, names As Variant
    years = ws.Range(ws.Cells(1, colYear), ws.Cells(lastRow, colYear)).Value
    caseIds = ws.Range(ws.Cells(1, colCase), ws.Cells(lastRow, colCase)).Value
    kubun1s = ws.Range(ws.Cells(1, colKubun1), ws.Cells(lastRow, colKubun1)).Value
    kubun2s = ws.Range(ws.Cells(1, colKubun2), ws.Cells(lastRow, colKubun2)).Value
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value
    names = ws.Range(ws.Cells(1, colName), ws.Cells(lastRow, colName)).Value

    Dim rowsByKey As Object
    Set rowsByKey = CreateObject("Scripting.Dictionary")   ' 重複判定キー → 該当行番号（カンマ区切り文字列）

    Dim r As Long
    For r = dataStartRow To lastRow
        If Trim(years(r, 1) & "") <> "" _
                And Trim(caseIds(r, 1) & "") <> "" _
                And Trim(names(r, 1) & "") <> "" _
                And Trim(kubun1s(r, 1) & "") <> "" _
                And Trim(kubun2s(r, 1) & "") <> "" _
                And Trim(yojitsus(r, 1) & "") <> "" Then
            Dim dupKey As String
            dupKey = years(r, 1) & "|" & caseIds(r, 1) & "|" & names(r, 1) & "|" & kubun1s(r, 1) & "|" & kubun2s(r, 1) & "|" & yojitsus(r, 1)

            If rowsByKey.Exists(dupKey) Then
                rowsByKey(dupKey) = rowsByKey(dupKey) & ", " & r
            Else
                rowsByKey(dupKey) = CStr(r)
            End If
        End If
    Next r

    ' 重複しているキーをすべて集めて、1回のエラーでまとめて報告する
    ' 併せて、重複グループごとに赤～オレンジ系の色を割り当てて対象セルに色を付ける
    Dim msg As String
    Dim key As Variant
    Dim palette As Variant
    palette = Array(RGB(255, 0, 0), RGB(255, 69, 0), RGB(255, 140, 0), RGB(220, 20, 60), RGB(178, 34, 34), RGB(255, 99, 71))
    Dim colorIdx As Long

    For Each key In rowsByKey.Keys
        If InStr(rowsByKey(key), ",") > 0 Then
            Dim rowParts() As String
            rowParts = Split(rowsByKey(key), ",")

            Dim p As Long
            Dim dupRows As String
            dupRows = ""
            For p = 1 To UBound(rowParts)
                If dupRows <> "" Then dupRows = dupRows & ","
                dupRows = dupRows & Trim(rowParts(p))
            Next p

            msg = msg & "基準行：" & Trim(rowParts(0)) & vbCrLf
            msg = msg & "重複行：" & dupRows & vbCrLf & vbCrLf

            Dim groupColor As Long
            groupColor = palette(colorIdx Mod (UBound(palette) + 1))

            For p = LBound(rowParts) To UBound(rowParts)
                Dim dupRow As Long
                dupRow = CLng(Trim(rowParts(p)))

                ws.Cells(dupRow, colYear).Font.Color = groupColor
                ws.Cells(dupRow, colCase).Font.Color = groupColor
                ws.Cells(dupRow, colName).Font.Color = groupColor
                ws.Cells(dupRow, colKubun1).Font.Color = groupColor
                ws.Cells(dupRow, colKubun2).Font.Color = groupColor
                ws.Cells(dupRow, colYojitsu).Font.Color = groupColor
            Next p

            colorIdx = colorIdx + 1
        End If
    Next key

    If msg <> "" Then
        Err.Raise vbObjectError + 1001, _
                  "CheckDuplicateRows", _
                  MAIN_SHEET_NAME & "に、条件（年度・案件ID・案件名・区分1・区分2・予実）が重複する行があります。" & vbCrLf & vbCrLf & _
                  msg & _
                  "実績反映を行う前に、" & MAIN_SHEET_NAME & "側の重複を解消してください。"
    End If
End Sub


' ============================
' 重複チェック対象の6列（年度・案件ID・案件名・区分1・区分2・予実）を、
' 指定範囲ぶん自動色に戻す
' ============================
Sub ResetDupHighlightColumns(ws As Worksheet, mapMainCol As Object, lastRow As Long)
    Dim dataStartRow As Long
    dataStartRow = GetMainDataStartRow()

    If lastRow < dataStartRow Then Exit Sub

    Dim dupCols As Variant
    dupCols = Array("年度", "案件ID", "案件名", "区分1", "区分2", "予実")

    Dim i As Long
    For i = LBound(dupCols) To UBound(dupCols)
        Dim col As Variant
        col = mapMainCol(dupCols(i))
        ws.Range(ws.Cells(dataStartRow, col), ws.Cells(lastRow, col)).Font.ColorIndex = xlAutomatic
    Next i
End Sub


' ============================
' 指定した名前のシートがブックに存在するか調べる
' ============================
Function SheetExists(wb As Workbook, sheetName As String) As Boolean
    Dim ws As Worksheet
    For Each ws In wb.Sheets
        If ws.Name = sheetName Then
            SheetExists = True
            Exit Function
        End If
    Next ws
    SheetExists = False
End Function


' ============================
' Other側の日付/年から年だけを安全に取り出す
' ============================
Function NormalizeYear(k1 As Variant) As Long
    If IsDate(k1) Then
        NormalizeYear = Year(CDate(k1))
    ElseIf IsNumeric(k1) Then
        NormalizeYear = CLng(k1)
    Else
        NormalizeYear = -1
    End If
End Function


' ============================
' 4月始まりの年度内での月の位置を返す（4月=1 … 3月=12）
' ============================
Function FiscalMonthPosition(calendarMonth As Long) As Long
    If calendarMonth >= 4 Then
        FiscalMonthPosition = calendarMonth - 3
    Else
        FiscalMonthPosition = calendarMonth + 9
    End If
End Function


' ============================
' 貼り付け前後で値が変わったセルだけ赤字にする
' （変わっていないセルは自動色に戻す）
' ============================
Sub HighlightChangedCells(rng As Range, oldVals As Variant, newVals As Variant)
    Dim i As Long

    If IsArray(oldVals) Then
        For i = 1 To rng.Cells.Count
            If CStr(newVals(1, i)) = "" Then
                ' 実績シート側にその値が存在しなかった
                rng.Cells(i).Font.Color = RGB(150, 150, 150)
            ElseIf CStr(oldVals(1, i)) <> CStr(newVals(1, i)) Then
                rng.Cells(i).Font.Color = RGB(0, 153, 0)
            Else
                rng.Cells(i).Font.ColorIndex = xlAutomatic
            End If
        Next i
    Else
        ' 範囲が1セルだけの場合、Valueは配列でなくスカラーになる
        If CStr(newVals) = "" Then
            rng.Font.Color = RGB(150, 150, 150)
        ElseIf CStr(oldVals) <> CStr(newVals) Then
            rng.Font.Color = RGB(0, 153, 0)
        Else
            rng.Font.ColorIndex = xlAutomatic
        End If
    End If
End Sub


' ============================
' Workbook_SheetBeforeDoubleClickの本体処理。
' 実績反映で変更されたセルをダブルクリックすると、除外（旧値に戻す）⇔解除をトグルする
' ============================
Sub HandleSheetBeforeDoubleClick(Sh As Object, Target As Range, Cancel As Boolean)
    If gToggleValuesByRow Is Nothing Then Exit Sub
    If Sh.Name <> MAIN_SHEET_NAME Then Exit Sub

    Dim mapMainRange As Object
    Set mapMainRange = GetMainRangeMap()
    Dim pasteRangeStartCol As Long, pasteRangeEndCol As Long
    pasteRangeStartCol = Sh.Range(mapMainRange("開始") & "1").Column
    pasteRangeEndCol = Sh.Range(mapMainRange("終了") & "1").Column

    If Target.Column < pasteRangeStartCol Or Target.Column > pasteRangeEndCol Then Exit Sub
    If Not gToggleValuesByRow.Exists(Target.Row) Then Exit Sub

    Dim info As Variant
    info = gToggleValuesByRow(Target.Row)

    Dim rowOldVals As Variant, rowNewVals As Variant
    rowOldVals = info(0)
    rowNewVals = info(1)

    Dim colIdx As Long
    colIdx = Target.Column - pasteRangeStartCol + 1

    If CStr(rowNewVals(1, colIdx)) = "" Then Exit Sub
    If CStr(rowOldVals(1, colIdx)) = CStr(rowNewVals(1, colIdx)) Then Exit Sub

    Dim changedColor As Long
    changedColor = RGB(0, 153, 0)

    Cancel = True   ' セル編集モードに入らないようにする

    Application.EnableEvents = False
    If Target.Font.Color = changedColor Then
        Target.Value = rowOldVals(1, colIdx)
        Target.Font.Color = RGB(255, 140, 0)   ' 除外中（実績なしのグレーとは区別する）
    Else
        Target.Value = rowNewVals(1, colIdx)
        Target.Font.Color = changedColor
    End If
    Application.EnableEvents = True
End Sub


' ============================
' 項目名（年度・案件ID・対象範囲-開始行など）に対応する、
' 実績シート側 or 計算算定シート側の値を返す
' ============================
Function GetItemValue(itemName As String, isMain As Boolean) As String
    If gItemMap Is Nothing Then LoadSystemMappings

    If Not gItemMap.Exists(itemName) Then
        Err.Raise vbObjectError + 1000, _
                  "GetItemValue", _
                  "システム用シートに項目「" & itemName & "」が見つかりません。"
    End If

    Dim arr As Variant
    arr = gItemMap(itemName)

    If isMain Then
        GetItemValue = arr(1)
    Else
        GetItemValue = arr(0)
    End If
End Function


' ============================
' 項目名（区分1・区分2など）の「実績シート値→計算算定シート値」マッピング辞書を返す
' ============================
Function GetDataMap(itemName As String) As Object
    If gDataMaps Is Nothing Then LoadSystemMappings

    If Not gDataMaps.Exists(itemName) Then
        Err.Raise vbObjectError + 1000, _
                  "GetDataMap", _
                  "システム用シートに項目「" & itemName & "」のデータマッピングが見つかりません。"
    End If

    Set GetDataMap = gDataMaps(itemName)
End Function


' ============================
' 計画算定シート側の列マッピング（年度・案件ID・案件名・区分1・区分2・予実 → 列記号）
' ============================
Function GetMainColMap() As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    dic("年度") = GetItemValue("年度", True)
    dic("案件ID") = GetItemValue("案件ID", True)
    dic("案件名") = GetItemValue("案件名", True)
    dic("区分1") = GetItemValue("区分1", True)
    dic("区分2") = GetItemValue("区分2", True)
    dic("予実") = GetItemValue("予実", True)

    Set GetMainColMap = dic
End Function


' ============================
' 実績シート側の列マッピング（年度・案件ID・区分1・区分2 → 列記号）
' ============================
Function GetOtherColMap() As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    dic("年度") = GetItemValue("年度", False)
    dic("案件ID") = GetItemValue("案件ID", False)
    dic("区分1") = GetItemValue("区分1", False)
    dic("区分2") = GetItemValue("区分2", False)

    Set GetOtherColMap = dic
End Function


' ============================
' 実績反映で行を照合する際のキーを構成する項目名（この並び順でキー文字列を組み立てる）。
' 各項目名はgItemMapのキーと一致しており、gDataMapsに同じ名前の変換表があれば
' その項目は実績シート側の値を変換してからキーに使う（無ければ生の値をそのまま使う）
' ============================
Function KeyItemNames() As Variant
    KeyItemNames = Array("年度", "案件ID", "区分1", "区分2")
End Function


' ============================
' 計画算定シート側の貼付範囲（開始・終了の列記号）
' ============================
Function GetMainRangeMap() As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    dic("開始") = GetItemValue("対象範囲-開始列", True)
    dic("終了") = GetItemValue("対象範囲-終了列", True)

    Set GetMainRangeMap = dic
End Function


' ============================
' 実績シート側の貼付範囲（開始・終了の列記号）
' ============================
Function GetOtherRangeMap() As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    dic("開始") = GetItemValue("対象範囲-開始列", False)
    dic("終了") = GetItemValue("対象範囲-終了列", False)

    Set GetOtherRangeMap = dic
End Function


' ============================
' 計画算定シート側のデータ開始行
' ============================
Function GetMainDataStartRow() As Long
    GetMainDataStartRow = CLng(GetItemValue("対象範囲-開始行", True))
End Function


' ============================
' 実績シート側のデータ開始行
' ============================
Function GetOtherDataStartRow() As Long
    GetOtherDataStartRow = CLng(GetItemValue("対象範囲-開始行", False))
End Function


' ============================
' システム用シートの「項目マッピング」表と、「データマッピング-XXX」というタイトルの
' 表をすべて、それぞれ1回だけ読み込み、gItemMap・gDataMapsにキャッシュする。
' 「データマッピング-XXX」は数がいくつあっても（区分3以降を追加しても）自動的に拾われる
' ============================
Sub LoadSystemMappings()
    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("システム用")

    Set gItemMap = LoadItemMapTable(ws, "項目マッピング")
    Set gDataMaps = LoadAllDataMaps(ws)
End Sub


' ============================
' システム用シート全体から「データマッピング-XXX」というタイトルのセルをすべて探し、
' XXXの部分を項目名として、それぞれの表をLoadPairMapTableで読み込む
' ============================
Function LoadAllDataMaps(ws As Worksheet) As Object
    Const TITLE_PREFIX As String = "データマッピング-"

    Dim result As Object
    Set result = CreateObject("Scripting.Dictionary")

    Dim cell As Range
    For Each cell In ws.UsedRange.Cells
        Dim titleText As String
        titleText = CStr(cell.Value)

        If Left(titleText, Len(TITLE_PREFIX)) = TITLE_PREFIX Then
            Dim itemName As String
            itemName = Mid(titleText, Len(TITLE_PREFIX) + 1)

            If itemName <> "" Then
                Set result(itemName) = LoadPairMapTable(ws, titleText)
            End If
        End If
    Next cell

    Set LoadAllDataMaps = result
End Function


' ============================
' 「(タイトル)」の1行下に「項目名｜実績シート｜計算算定シート」という3列の見出しが続く表を読み込み、
' 項目名 → Array(実績シート値, 計算算定シート値) の辞書にする
' ============================
Function LoadItemMapTable(ws As Worksheet, titleText As String) As Object
    Dim titleCell As Range
    Set titleCell = ws.Cells.Find(What:=titleText, LookIn:=xlValues, LookAt:=xlWhole, _
                                   SearchOrder:=xlByRows, MatchCase:=False)

    If titleCell Is Nothing Then
        Err.Raise vbObjectError + 1000, _
                  "LoadItemMapTable", _
                  "システム用シートに見出し「" & titleText & "」が見つかりません。"
    End If

    Dim headerRow As Long
    headerRow = titleCell.Row + 1   ' タイトルの1行下が「項目名」「実績シート」「計算算定シート」の見出し行

    Dim colItem As Long, colJisseki As Long, colKeisan As Long
    colItem = FindHeaderColumn(ws, headerRow, titleCell.Column, "項目名")
    colJisseki = FindHeaderColumn(ws, headerRow, titleCell.Column, "実績シート")
    colKeisan = FindHeaderColumn(ws, headerRow, titleCell.Column, "計算算定シート")

    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    Dim r As Long
    r = headerRow + 1

    ' 空行に当たるまで読み込む
    Do While ws.Cells(r, colItem).Value <> ""
        Dim itemName As String
        Dim jissekiVal As String, keisanVal As String

        itemName = ws.Cells(r, colItem).Value
        jissekiVal = ws.Cells(r, colJisseki).Value
        keisanVal = ws.Cells(r, colKeisan).Value

        dic(itemName) = Array(jissekiVal, keisanVal)

        r = r + 1
    Loop

    Set LoadItemMapTable = dic
End Function


' ============================
' 「(タイトル)」の1行下に「実績シート｜計算算定シート」という2列の見出しが続く表を読み込み、
' 「実績シート値→計算算定シート値」の辞書にする
' ============================
Function LoadPairMapTable(ws As Worksheet, titleText As String) As Object
    Dim titleCell As Range
    Set titleCell = ws.Cells.Find(What:=titleText, LookIn:=xlValues, LookAt:=xlWhole, _
                                   SearchOrder:=xlByRows, MatchCase:=False)

    If titleCell Is Nothing Then
        Err.Raise vbObjectError + 1000, _
                  "LoadPairMapTable", _
                  "システム用シートに見出し「" & titleText & "」が見つかりません。"
    End If

    Dim headerRow As Long
    headerRow = titleCell.Row + 1   ' タイトルの1行下が「実績シート」「計算算定シート」の見出し行

    Dim colJisseki As Long, colKeisan As Long
    colJisseki = FindHeaderColumn(ws, headerRow, titleCell.Column, "実績シート")
    colKeisan = FindHeaderColumn(ws, headerRow, titleCell.Column, "計算算定シート")

    Dim result As Object
    Set result = CreateObject("Scripting.Dictionary")

    Dim r As Long
    r = headerRow + 1

    ' 空行に当たるまで読み込む
    Do While ws.Cells(r, colJisseki).Value <> ""
        Dim jissekiKey As String
        jissekiKey = ws.Cells(r, colJisseki).Value
        If jissekiKey <> "" Then result(jissekiKey) = ws.Cells(r, colKeisan).Value

        r = r + 1
    Loop

    Set LoadPairMapTable = result
End Function


' ============================
' 指定行の中から、指定列以降・数列以内で指定文字列と完全一致するセルの列番号を返す。
' 検索範囲をタイトル列の近く（数列以内）に絞ることで、同じ行にある他の表の
' 同名見出し（複数の表が「実績シート」「計算算定シート」を使い回すため）を誤って拾わないようにする
' ============================
Function FindHeaderColumn(ws As Worksheet, headerRow As Long, startCol As Long, headerText As String) As Long
    Const SEARCH_WIDTH As Long = 3

    Dim searchRange As Range
    Set searchRange = ws.Cells(headerRow, startCol).Resize(1, SEARCH_WIDTH)

    Dim c As Range
    Set c = searchRange.Find(What:=headerText, LookIn:=xlValues, LookAt:=xlWhole, _
                              SearchOrder:=xlByColumns, MatchCase:=False)

    If c Is Nothing Then
        Err.Raise vbObjectError + 1000, _
                  "FindHeaderColumn", _
                  headerRow & "行目（" & startCol & "列目から" & SEARCH_WIDTH & "列以内）に見出し「" & headerText & "」が見つかりません。"
    End If

    FindHeaderColumn = c.Column
End Function
