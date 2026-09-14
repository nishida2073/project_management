Option Explicit

Private Const MAIN_SHEET_NAME As String = "計画算定シート"

' 保存前に累積された「本当の元の値・元のフォント色」（行番号 → Array(元値の配列, 元色の配列)）。
' 行ごとに最初に触られた時点の状態を保持し続け、保存時にクリアする
Private gUndoBackupRows As Object

' 「元に戻す」用の履歴（スタック）。各要素はgUndoBackupRowsのスナップショット（Dictionary）
Private gUndoHistory As Collection

' 実績反映で変更のあった行の元値・新値（行番号 → Array(元値の配列, 新値の配列)）
Private gToggleValuesByRow As Object

' 重複行ハイライトを付ける前の、年度・案件ID・会計区分1・会計区分2列のフォント色
' （行番号 → Array(年度の色, 案件IDの色, 会計区分1の色, 会計区分2の色)）
Private gDuplicateHighlightBackup As Object

' 前回保存時点（＝直近のHandleBeforeSave完了時、なければファイルを開いた時点）の
' 貼付範囲全行の値・フォント色（行番号 → Array(値の配列, 色の配列)）。
' 保存のたびにこの内容と現在のシートを比較し、差分があれば（実績反映・手動編集を問わず）履歴に積む
Private gLastSavedSnapshot As Object

' 前回チェック時点の計画算定シート最終行（行の追加・削除を検知するため）
Private gLastKnownMainLastRow As Long
Private gLastKnownMainLastRowValid As Boolean

' システム用シートのマッピング全体のキャッシュ（ヘッダー名 → Dictionary(キー→値)）。
' LoadMappingHorizontalを呼ぶたびにシートを走査し直さないよう、初回だけ読み込んで使い回す
Private gAllMappings As Object

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
    Set mapMainCol = LoadMappingHorizontal("計算算定シート-項目")
    Set mapMainRange = LoadMappingHorizontal("計算算定シート-対象範囲")
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
    Dim mapMainRange As Object
    Dim mapMainCol As Object

    Set mapMainRange = LoadMappingHorizontal("計算算定シート-対象範囲")
    Set mapMainCol = LoadMappingHorizontal("計算算定シート-項目")

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

    ' 重複行ハイライトも、元のフォント色へ戻す
    If Not gDuplicateHighlightBackup Is Nothing Then
        Dim colYear As Variant, colCase As Variant, colName As Variant, colKaikeiKubun1 As Variant, colKaikeiKubun2 As Variant, colYojitsu As Variant
        colYear = mapMainCol("年度")
        colCase = mapMainCol("案件ID")
        colName = mapMainCol("案件名")
        colKaikeiKubun1 = mapMainCol("会計区分1")
        colKaikeiKubun2 = mapMainCol("会計区分2")
        colYojitsu = mapMainCol("予実")

        Dim dupKey As Variant
        For Each dupKey In gDuplicateHighlightBackup.Keys
            Dim dupRow As Long
            dupRow = dupKey

            Dim dupColors As Variant
            dupColors = gDuplicateHighlightBackup(dupKey)

            ws.Cells(dupRow, colYear).Font.Color = dupColors(0)
            ws.Cells(dupRow, colCase).Font.Color = dupColors(1)
            ws.Cells(dupRow, colName).Font.Color = dupColors(2)
            ws.Cells(dupRow, colKaikeiKubun1).Font.Color = dupColors(3)
            ws.Cells(dupRow, colKaikeiKubun2).Font.Color = dupColors(4)
            ws.Cells(dupRow, colYojitsu).Font.Color = dupColors(5)
        Next dupKey

        Set gDuplicateHighlightBackup = CreateObject("Scripting.Dictionary")
    End If

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

    If lastRow >= 5 Then
        Dim r As Long
        For r = 5 To lastRow
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
    Set gDuplicateHighlightBackup = CreateObject("Scripting.Dictionary")

    ' 行番号が信頼できなくなったため、個々の行の「元の色」には戻せない。
    ' 代わりに、ハイライト対象になり得る列を貼付範囲・重複チェック列とも一括で自動色に戻す
    Dim lastRow As Long
    lastRow = ws.Cells(ws.Rows.Count, mapMainCol("年度")).End(xlUp).Row
    If lastRow >= 5 Then
        ws.Range(mapMainRange("開始") & "5:" & mapMainRange("終了") & lastRow).Font.ColorIndex = xlAutomatic

        Dim dupCols As Variant
        dupCols = Array("年度", "案件ID", "案件名", "会計区分1", "会計区分2", "予実")
        Dim i As Long
        For i = LBound(dupCols) To UBound(dupCols)
            ws.Range(ws.Cells(5, mapMainCol(dupCols(i))), ws.Cells(lastRow, mapMainCol(dupCols(i)))).Font.ColorIndex = xlAutomatic
        Next i
    End If

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

    Dim wbOther As Workbook
    Dim wsOther As Worksheet
    Dim wsMain As Worksheet
    Dim lastRowOther As Long
    Dim lastRowMain As Long
    Dim otherRow As Long
    Dim otherYearRaw As Variant, otherCaseId As Variant, otherKubunText As Variant, otherCostKubunId As Variant
    Dim foundRow As Long
    Dim otherFilePathToOpen As Variant

    Dim mapOtherCol As Object
    Dim mapMainRange As Object
    Dim mapOtherRange As Object
    Dim mapMainCol As Object
    Dim mapKaikeiKubun1 As Object
    Dim mapKaikeiKubun2 As Object
    Dim mainIndex As Object

    Dim yOther As Long
    Dim kaikeiKubun1 As String, kaikeiKubun2 As String
    Dim idxKey As String

    Dim mainRange As Range, otherRange As Range
    Dim oldVals As Variant, newVals As Variant
    Dim completed As Boolean
    Dim matchedRows As Object

    Dim reflectedCount As Long           ' 反映件数
    Dim skipJissekiOnlyCount As Long     ' スキップ件数（実績）：実績シートにはあるが計画算定シートにない
    Dim skipKeikakuOnlyCount As Long     ' スキップ件数（計画）：計画算定シートにはあるが実績シートにない
    Dim skipDupCount As Long             ' スキップ件数（実績重複）

    Dim reflectedRows As String          ' 反映した「実績行→計画行」の一覧
    Dim skipJissekiOnlyRows As String    ' スキップ（実績）の実績シート側行番号の一覧
    Dim skipKeikakuOnlyRows As String    ' スキップ（計画）の計画算定シート側行番号の一覧
    Dim skipDupRows As String            ' スキップ（実績重複）の実績シート側行番号の一覧

    Dim years As Variant, caseIds As Variant, kubuns As Variant, costKubuns As Variant

    Dim startPos As Long, endPos As Long

    ' ここ以降のエラーは全て CleanFail で拾う
    On Error GoTo CleanFail

    Set wsMain = ThisWorkbook.Sheets(MAIN_SHEET_NAME)
    Set mapMainCol = LoadMappingHorizontal("計算算定シート-項目")
    Set mapMainRange = LoadMappingHorizontal("計算算定シート-対象範囲")

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
    Set mapOtherCol = LoadMappingHorizontal("実績シート-項目")
    Set mapOtherRange = LoadMappingHorizontal("実績シート-対象範囲")
    Set mapKaikeiKubun1 = LoadMappingHorizontal("会計区分1マッピング")
    Set mapKaikeiKubun2 = LoadMappingHorizontal("会計区分2マッピング")

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

    ' === ⑥ Otherの可変範囲の最終行を取得し、必要な列を一括で配列に読み込む ===
    lastRowOther = wsOther.Cells(wsOther.Rows.Count, mapOtherCol("年度")).End(xlUp).Row

    If lastRowOther >= 2 Then
        years = wsOther.Range(wsOther.Cells(1, mapOtherCol("年度")), wsOther.Cells(lastRowOther, mapOtherCol("年度"))).Value
        caseIds = wsOther.Range(wsOther.Cells(1, mapOtherCol("案件ID")), wsOther.Cells(lastRowOther, mapOtherCol("案件ID"))).Value
        kubuns = wsOther.Range(wsOther.Cells(1, mapOtherCol("区分")), wsOther.Cells(lastRowOther, mapOtherCol("区分"))).Value
        costKubuns = wsOther.Range(wsOther.Cells(1, mapOtherCol("原価区分ID")), wsOther.Cells(lastRowOther, mapOtherCol("原価区分ID"))).Value
    End If

    ' 実績反映時の行検索用に、計画算定シート側の索引を作る
    Set mainIndex = BuildMainIndex(wsMain, mapMainCol, lastRowMain)

    ' === ⑦ 行ループ（キーの判定は配列上で行い、一致した行だけシートへアクセスする） ===
    For otherRow = 2 To lastRowOther

        ' キー4つ取得（年度, 案件ID, 区分, 原価区分ID）
        otherYearRaw = years(otherRow, 1)
        otherCaseId = caseIds(otherRow, 1)
        otherKubunText = Trim(CStr(kubuns(otherRow, 1)))
        otherCostKubunId = Trim(CStr(costKubuns(otherRow, 1)))

        If mapKaikeiKubun1.Exists(otherKubunText) And mapKaikeiKubun2.Exists(otherCostKubunId) Then

            yOther = NormalizeYear(otherYearRaw)
            kaikeiKubun1 = mapKaikeiKubun1(otherKubunText)
            kaikeiKubun2 = mapKaikeiKubun2(otherCostKubunId)
            idxKey = yOther & "|" & otherCaseId & "|" & kaikeiKubun1 & "|" & kaikeiKubun2

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

    Dim mapMainRange As Object, mapMainCol As Object
    Set mapMainRange = LoadMappingHorizontal("計算算定シート-対象範囲")
    Set mapMainCol = LoadMappingHorizontal("計算算定シート-項目")

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

    If lastRow < 5 Then Exit Sub

    Dim colYojitsu As Variant
    colYojitsu = mapMainCol("予実")

    Dim yojitsus As Variant
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value

    Dim r As Long
    For r = 5 To lastRow
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
' Main側の「年度|案件ID|会計区分1|会計区分2」→行番号 の索引を作る
' ============================
Function BuildMainIndex(ws As Worksheet, mapMainCol As Object, lastRow As Long) As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    If lastRow < 5 Then
        Set BuildMainIndex = dic
        Exit Function
    End If

    Dim colYear As Variant, colCase As Variant, colKaikeiKubun1 As Variant, colKaikeiKubun2 As Variant, colYojitsu As Variant
    colYear = mapMainCol("年度")
    colCase = mapMainCol("案件ID")
    colKaikeiKubun1 = mapMainCol("会計区分1")
    colKaikeiKubun2 = mapMainCol("会計区分2")
    colYojitsu = mapMainCol("予実")

    Dim years As Variant, caseIds As Variant, kaikeiKubun1s As Variant, kaikeiKubun2s As Variant, yojitsus As Variant
    years = ws.Range(ws.Cells(1, colYear), ws.Cells(lastRow, colYear)).Value
    caseIds = ws.Range(ws.Cells(1, colCase), ws.Cells(lastRow, colCase)).Value
    kaikeiKubun1s = ws.Range(ws.Cells(1, colKaikeiKubun1), ws.Cells(lastRow, colKaikeiKubun1)).Value
    kaikeiKubun2s = ws.Range(ws.Cells(1, colKaikeiKubun2), ws.Cells(lastRow, colKaikeiKubun2)).Value
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value

    Dim r As Long
    For r = 5 To lastRow
        If yojitsus(r, 1) = "実績" _
                And Trim(years(r, 1) & "") <> "" _
                And Trim(caseIds(r, 1) & "") <> "" _
                And Trim(kaikeiKubun1s(r, 1) & "") <> "" _
                And Trim(kaikeiKubun2s(r, 1) & "") <> "" Then
            Dim idxKey As String
            idxKey = years(r, 1) & "|" & caseIds(r, 1) & "|" & kaikeiKubun1s(r, 1) & "|" & kaikeiKubun2s(r, 1)

            If Not dic.Exists(idxKey) Then dic(idxKey) = r
        End If
    Next r

    Set BuildMainIndex = dic
End Function


' ============================
' 年度・案件ID・案件名・会計区分1・会計区分2・予実（remove-duplicate-rows.ps1と同じキー）の
' 重複チェックを行う。前回のチェックで付けた重複ハイライトは一旦元の色に戻したうえで判定し直し、
' 重複が見つかった場合は行をハイライトしたうえでエラーを発生させる
' ============================
Sub CheckDuplicateRows(ws As Worksheet, mapMainCol As Object, lastRow As Long)
    Dim colYear As Variant, colCase As Variant, colName As Variant, colKaikeiKubun1 As Variant, colKaikeiKubun2 As Variant, colYojitsu As Variant
    colYear = mapMainCol("年度")
    colCase = mapMainCol("案件ID")
    colName = mapMainCol("案件名")
    colKaikeiKubun1 = mapMainCol("会計区分1")
    colKaikeiKubun2 = mapMainCol("会計区分2")
    colYojitsu = mapMainCol("予実")

    ' 前回までのチェックで重複ハイライトを付けた行は、一旦「本当の元の色」に戻す。
    ' そのうえで記録をクリアし、今回のチェックで改めて重複判定・色付けを行う
    If Not gDuplicateHighlightBackup Is Nothing Then
        Dim resetDupKey As Variant
        For Each resetDupKey In gDuplicateHighlightBackup.Keys
            Dim resetDupRow As Long
            resetDupRow = resetDupKey
            Dim resetDupColors As Variant
            resetDupColors = gDuplicateHighlightBackup(resetDupKey)
            ws.Cells(resetDupRow, colYear).Font.Color = resetDupColors(0)
            ws.Cells(resetDupRow, colCase).Font.Color = resetDupColors(1)
            ws.Cells(resetDupRow, colName).Font.Color = resetDupColors(2)
            ws.Cells(resetDupRow, colKaikeiKubun1).Font.Color = resetDupColors(3)
            ws.Cells(resetDupRow, colKaikeiKubun2).Font.Color = resetDupColors(4)
            ws.Cells(resetDupRow, colYojitsu).Font.Color = resetDupColors(5)
        Next resetDupKey
    End If
    Set gDuplicateHighlightBackup = CreateObject("Scripting.Dictionary")

    If lastRow < 5 Then Exit Sub

    Dim years As Variant, caseIds As Variant, kaikeiKubun1s As Variant, kaikeiKubun2s As Variant, yojitsus As Variant, names As Variant
    years = ws.Range(ws.Cells(1, colYear), ws.Cells(lastRow, colYear)).Value
    caseIds = ws.Range(ws.Cells(1, colCase), ws.Cells(lastRow, colCase)).Value
    kaikeiKubun1s = ws.Range(ws.Cells(1, colKaikeiKubun1), ws.Cells(lastRow, colKaikeiKubun1)).Value
    kaikeiKubun2s = ws.Range(ws.Cells(1, colKaikeiKubun2), ws.Cells(lastRow, colKaikeiKubun2)).Value
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value
    names = ws.Range(ws.Cells(1, colName), ws.Cells(lastRow, colName)).Value

    Dim rowsByKey As Object
    Set rowsByKey = CreateObject("Scripting.Dictionary")   ' 重複判定キー → 該当行番号（カンマ区切り文字列）

    Dim r As Long
    For r = 5 To lastRow
        If Trim(years(r, 1) & "") <> "" _
                And Trim(caseIds(r, 1) & "") <> "" _
                And Trim(names(r, 1) & "") <> "" _
                And Trim(kaikeiKubun1s(r, 1) & "") <> "" _
                And Trim(kaikeiKubun2s(r, 1) & "") <> "" _
                And Trim(yojitsus(r, 1) & "") <> "" Then
            Dim dupKey As String
            dupKey = years(r, 1) & "|" & caseIds(r, 1) & "|" & names(r, 1) & "|" & kaikeiKubun1s(r, 1) & "|" & kaikeiKubun2s(r, 1) & "|" & yojitsus(r, 1)

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

                If Not gDuplicateHighlightBackup.Exists(dupRow) Then
                    gDuplicateHighlightBackup(dupRow) = Array( _
                        ws.Cells(dupRow, colYear).Font.Color, _
                        ws.Cells(dupRow, colCase).Font.Color, _
                        ws.Cells(dupRow, colName).Font.Color, _
                        ws.Cells(dupRow, colKaikeiKubun1).Font.Color, _
                        ws.Cells(dupRow, colKaikeiKubun2).Font.Color, _
                        ws.Cells(dupRow, colYojitsu).Font.Color)
                End If

                ws.Cells(dupRow, colYear).Font.Color = groupColor
                ws.Cells(dupRow, colCase).Font.Color = groupColor
                ws.Cells(dupRow, colName).Font.Color = groupColor
                ws.Cells(dupRow, colKaikeiKubun1).Font.Color = groupColor
                ws.Cells(dupRow, colKaikeiKubun2).Font.Color = groupColor
                ws.Cells(dupRow, colYojitsu).Font.Color = groupColor
            Next p

            colorIdx = colorIdx + 1
        End If
    Next key

    If msg <> "" Then
        Err.Raise vbObjectError + 1001, _
                  "CheckDuplicateRows", _
                  MAIN_SHEET_NAME & "に、条件（年度・案件ID・案件名・会計区分1・会計区分2・予実）が重複する行があります。" & vbCrLf & vbCrLf & _
                  msg & _
                  "実績反映を行う前に、" & MAIN_SHEET_NAME & "側の重複を解消してください。"
    End If
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
    Set mapMainRange = LoadMappingHorizontal("計算算定シート-対象範囲")
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
' 指定ヘッダーの「下方向2列」のマッピングを返す。
' システム用シートの全ヘッダー分は初回呼び出し時にまとめて読み込み、以降はキャッシュを使い回す
' ============================
Function LoadMappingHorizontal(headerText As String) As Object
    If gAllMappings Is Nothing Then LoadAllMappings

    ' ★ ヘッダーが見つからなかった場合は強制終了
    If Not gAllMappings.Exists(headerText) Then
        Err.Raise vbObjectError + 1000, _
                  "LoadMappingHorizontal", _
                  "ヘッダー「" & headerText & "」が見つかりません。"
    End If

    Set LoadMappingHorizontal = gAllMappings(headerText)
End Function


' ============================
' システム用シートのヘッダー行（2行目）を1回だけ横方向に走査し、
' ヘッダー名ごとの下方向マッピングをまとめてgAllMappingsに読み込む
' ============================
Sub LoadAllMappings()
    Set gAllMappings = CreateObject("Scripting.Dictionary")

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("システム用")

    Const HEADER_ROW As Long = 2
    Const DATA_START_ROW As Long = HEADER_ROW + 1

    Dim lastCol As Long
    lastCol = ws.Cells(HEADER_ROW, ws.Columns.Count).End(xlToLeft).Column

    Dim c As Long
    For c = 1 To lastCol
        Dim headerText As String
        headerText = ws.Cells(HEADER_ROW, c).Value

        If headerText <> "" Then
            Dim dic As Object
            Set dic = CreateObject("Scripting.Dictionary")
            Set gAllMappings(headerText) = dic

            Dim r As Long
            r = DATA_START_ROW

            ' 空行に当たるまで読み込む
            Do While ws.Cells(r, c).Value <> ""
                Dim key As String
                Dim val As String

                key = ws.Cells(r, c).Value
                val = ws.Cells(r, c + 1).Value ' 右隣の列が値

                If key <> "" Then dic(key) = val

                r = r + 1
            Loop
        End If
    Next c
End Sub
