Option Explicit

Private Const MAIN_SHEET_NAME As String = "計画算定シート"

' Trueの場合、実績反映（対話実行）時に反映月の範囲を指定するダイアログを表示する。Falseの場合は常に全期間を反映する
Private Const USE_MONTH_RANGE_DIALOG As Boolean = False

' 直前の実績反映で上書きした行のバックアップ（行番号 → Array(旧値, 旧フォント色)）
Private gBackupRows As Object

' 実績反映で変更のあった行の旧値・新値（行番号 → Array(旧値の配列, 新値の配列)）
Private gPendingReviewRows As Object

' 貼付範囲の開始・終了列のキャッシュ（選択変更のたびにLoadMappingHorizontalを呼び直さないため）
Private gPasteRangeStartCol As Long
Private gPasteRangeEndCol As Long
Private gPasteRangeCached As Boolean

' 重複行ハイライトを付ける前の、年度・案件ID・会計区分1・会計区分2列のフォント色
' （行番号 → Array(年度の色, 案件IDの色, 会計区分1の色, 会計区分2の色)）
Private gDuplicateHighlightBackup As Object

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

    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")
    Set mapMainCol = LoadMappingHorizontal("原価管理Excel")

    ' 実績反映・実績なしグレー化した行は、値はそのままに元のフォント色へ戻す
    If Not gBackupRows Is Nothing Then
        Dim key As Variant
        For Each key In gBackupRows.Keys
            Dim foundRow As Long
            foundRow = key

            Dim rng As Range
            Set rng = ws.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)

            Dim backupData As Variant
            backupData = gBackupRows(key)
            SetFontColors rng, backupData(1)   ' (0)=旧値, (1)=旧フォント色。値には触れない
        Next key
    End If

    ' 重複行ハイライトも、元のフォント色へ戻す
    If Not gDuplicateHighlightBackup Is Nothing Then
        Dim colYear As Variant, colCase As Variant, colQ As Variant, colR As Variant
        colYear = mapMainCol("年度")
        colCase = mapMainCol("案件ID")
        colQ = mapMainCol("会計区分1")
        colR = mapMainCol("会計区分2")

        Dim dupKey As Variant
        For Each dupKey In gDuplicateHighlightBackup.Keys
            Dim dupRow As Long
            dupRow = dupKey

            Dim dupColors As Variant
            dupColors = gDuplicateHighlightBackup(dupKey)

            ws.Cells(dupRow, colYear).Font.Color = dupColors(0)
            ws.Cells(dupRow, colCase).Font.Color = dupColors(1)
            ws.Cells(dupRow, colQ).Font.Color = dupColors(2)
            ws.Cells(dupRow, colR).Font.Color = dupColors(3)
        Next dupKey

        Set gDuplicateHighlightBackup = CreateObject("Scripting.Dictionary")
    End If

    Set gPendingReviewRows = CreateObject("Scripting.Dictionary")

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
    CreateButton wsMain, "UndoProcButton999", "E2", "元に戻す", "UndoLastImport"

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
    Dim r As Long
    Dim key1 As Variant, key2 As Variant, key3 As Variant, key4 As Variant
    Dim foundRow As Long
    Dim f As Variant

    Dim mapOtherCol As Object
    Dim mapMainRange As Object
    Dim mapOtherRange As Object
    Dim mapMainCol As Object
    Dim mapQ As Object
    Dim mapR As Object
    Dim mainIndex As Object

    Dim yOther As Long
    Dim qMain As String, rMain As String
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
    Set mapMainCol = LoadMappingHorizontal("原価管理Excel")

    ' === ① 対象ファイルを選ぶ前に、計画算定シート側の重複チェックを行う ===
    lastRowMain = wsMain.Cells(wsMain.Rows.Count, mapMainCol("年度")).End(xlUp).Row
    Set mainIndex = BuildMainIndex(wsMain, mapMainCol, lastRowMain)

    ' === ② 対話実行はファイルダイアログ、バッチ実行は引数のパスを使う ===
    If isInteractive Then
        f = Application.GetOpenFilename("Excelファイル (*.xlsx), *.xlsx")
        If f = False Then Exit Function
    Else
        f = otherFilePath
    End If

    ' === ③ Otherブックを開く ===
    Set wbOther = Workbooks.Open(f, ReadOnly:=True)

    If Not SheetExists(wbOther, "実績") Then
        ImportFromOtherBook = "選択したファイルに「実績」シートが見つかりません。" & vbCrLf & _
               "ファイルが正しいか確認してください。" & vbCrLf & "対象ファイル: " & f
        If isInteractive Then MsgBox ImportFromOtherBook, vbExclamation
        GoTo CleanExit
    End If

    ' === ③' 対話実行時のみ、反映する月の範囲を聞く（バッチ実行時は全期間） ===
    If isInteractive And USE_MONTH_RANGE_DIALOG Then
        Dim monthRangeStr As String
        Dim rangeParts() As String
        Dim startMonthStr As String, endMonthStr As String
        Dim startMonth As Long, endMonth As Long
        Dim isValidRange As Boolean
        isValidRange = False

        Do While Not isValidRange
            monthRangeStr = InputBox("反映する月の範囲を「開始月-終了月」の形式で入力してください（例：4-9）", "反映月の指定", "4-3")
            If monthRangeStr = "" Then monthRangeStr = "4-3"   ' 空の場合は全期間として扱う

            rangeParts = Split(monthRangeStr, "-")
            If UBound(rangeParts) <> 1 Then
                MsgBox "月の範囲は「開始月-終了月」の形式（例：4-9）で入力してください。", vbExclamation
                GoTo RetryMonthRange
            End If

            startMonthStr = Trim(rangeParts(0))
            endMonthStr = Trim(rangeParts(1))
            If startMonthStr = "" Then startMonthStr = "4"   ' 開始月省略時は4月扱い
            If endMonthStr = "" Then endMonthStr = "3"       ' 終了月省略時は3月扱い

            If Not IsNumeric(startMonthStr) Or Not IsNumeric(endMonthStr) Then
                MsgBox "月の範囲は「開始月-終了月」の形式（例：4-9）で入力してください。", vbExclamation
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

    ' === ④ マッピングは1回だけ読み込む ===
    Set mapOtherCol = LoadMappingHorizontal("実績Excel")
    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")
    Set mapOtherRange = LoadMappingHorizontal("実績Excel貼付範囲")
    Set mapQ = LoadMappingHorizontal("会計区分1マッピング")
    Set mapR = LoadMappingHorizontal("会計区分2マッピング")

    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    Application.EnableEvents = False

    ' 保存前の前回実行分が残っていれば、今回の反映前に一度元に戻しておく
    ' （残したまま次を反映すると、前回の反映結果を基準に比較してしまい、ハイライトが正しく付かないため）
    RevertBackedUpRows wsMain, mapMainRange

    ' 今回の実行分のバックアップを新規に用意
    Set gBackupRows = CreateObject("Scripting.Dictionary")
    Set matchedRows = CreateObject("Scripting.Dictionary")
    Set gPendingReviewRows = CreateObject("Scripting.Dictionary")

    ' === ⑤ Otherの可変範囲の最終行を取得し、必要な列を一括で配列に読み込む ===
    lastRowOther = wsOther.Cells(wsOther.Rows.Count, mapOtherCol("年度")).End(xlUp).Row

    If lastRowOther >= 2 Then
        years = wsOther.Range(wsOther.Cells(1, mapOtherCol("年度")), wsOther.Cells(lastRowOther, mapOtherCol("年度"))).Value
        caseIds = wsOther.Range(wsOther.Cells(1, mapOtherCol("案件ID")), wsOther.Cells(lastRowOther, mapOtherCol("案件ID"))).Value
        kubuns = wsOther.Range(wsOther.Cells(1, mapOtherCol("区分")), wsOther.Cells(lastRowOther, mapOtherCol("区分"))).Value
        costKubuns = wsOther.Range(wsOther.Cells(1, mapOtherCol("原価区分ID")), wsOther.Cells(lastRowOther, mapOtherCol("原価区分ID"))).Value
    End If

    ' === ⑥ 行ループ（キーの判定は配列上で行い、一致した行だけシートへアクセスする） ===
    For r = 2 To lastRowOther

        ' キー4つ取得（年度, 案件ID, 区分, 原価区分ID）
        key1 = years(r, 1)
        key2 = caseIds(r, 1)
        key3 = Trim(CStr(kubuns(r, 1)))
        key4 = Trim(CStr(costKubuns(r, 1)))

        If mapQ.Exists(key3) And mapR.Exists(key4) Then

            yOther = NormalizeYear(key1)
            qMain = mapQ(key3)
            rMain = mapR(key4)
            idxKey = yOther & "|" & key2 & "|" & qMain & "|" & rMain

            ' === ⑦ Dictionaryで一致する行を即座に取得 ===
            If mainIndex.Exists(idxKey) Then
                foundRow = mainIndex(idxKey)

                ' 実績シート側に重複行があり、同じ行へ既に反映済みの場合は再処理しない
                ' （2回目以降の処理が「1回目で上書きした後の値」を元に比較してしまい、
                '   正しく付いた赤色やUndo用バックアップが誤って上書きされるため）
                If Not matchedRows.Exists(foundRow) Then
                    matchedRows(foundRow) = True

                    ' === ⑧ 一致した行に貼り付け（値が変わったセルだけ赤色にする） ===
                    Set mainRange = wsMain.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)
                    Set otherRange = wsOther.Range(mapOtherRange("開始") & r & ":" & mapOtherRange("終了") & r)

                    Dim oldColors As Variant
                    oldColors = GetFontColors(mainRange)   ' 上書き前のフォント色を保持

                    Dim otherVals As Variant
                    otherVals = otherRange.Value

                    oldVals = mainRange.Value          ' 上書き前の値を保持

                    ' 1列目（過年度）は常に反映し、2列目以降（4月～翌3月）は指定範囲の月だけ反映する
                    Dim mergedVals As Variant
                    mergedVals = oldVals
                    Dim colOffset As Long
                    For colOffset = 1 To mainRange.Cells.Count
                        If colOffset = 1 Or ((colOffset - 1) >= startPos And (colOffset - 1) <= endPos) Then
                            mergedVals(1, colOffset) = otherVals(1, colOffset)
                        End If
                    Next colOffset

                    mainRange.Value = mergedVals
                    newVals = mainRange.Value

                    gBackupRows(foundRow) = Array(oldVals, oldColors)
                    gPendingReviewRows(foundRow) = Array(oldVals, newVals)

                    HighlightChangedCells mainRange, oldVals, newVals

                    reflectedCount = reflectedCount + 1
                    reflectedRows = AppendItem(reflectedRows, r & "→" & foundRow)
                Else
                    skipDupCount = skipDupCount + 1
                    skipDupRows = AppendItem(skipDupRows, CStr(r))
                End If
            Else
                skipJissekiOnlyCount = skipJissekiOnlyCount + 1
                skipJissekiOnlyRows = AppendItem(skipJissekiOnlyRows, CStr(r))
            End If

        Else
            skipJissekiOnlyCount = skipJissekiOnlyCount + 1
            skipJissekiOnlyRows = AppendItem(skipJissekiOnlyRows, CStr(r))
        End If

    Next r

    ' === ⑨ 一度もマッチしなかった「予実=実績」行をグレー表示にする ===
    MarkUnmatchedActualRows wsMain, mapMainCol, mapMainRange, matchedRows, gBackupRows, lastRowMain, skipKeikakuOnlyCount, skipKeikakuOnlyRows

    completed = True

CleanExit:
    Application.EnableEvents = True
    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = True

    If Not wbOther Is Nothing Then wbOther.Close SaveChanges:=False

    If completed Then
        Dim monthRangeLine As String
        If isInteractive And USE_MONTH_RANGE_DIALOG Then
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
    End If

    ImportFromOtherBook = "エラーが発生しました。" & vbCrLf & errDescription
    If isInteractive Then MsgBox ImportFromOtherBook
    Resume CleanExit

End Function


' ============================
' 直前の実績反映を元に戻す
' ============================
Sub UndoLastImport()

    Dim noHistory As Boolean
    noHistory = (gBackupRows Is Nothing)
    If Not noHistory Then noHistory = (gBackupRows.Count = 0)

    If noHistory Then
        MsgBox "実行履歴がありません。"
        Exit Sub
    End If

    Dim wsMain As Worksheet
    Set wsMain = ThisWorkbook.Sheets(MAIN_SHEET_NAME)

    Dim mapMainRange As Object
    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")

    Application.ScreenUpdating = False
    Application.Calculation = xlCalculationManual
    Application.EnableEvents = False

    RevertBackedUpRows wsMain, mapMainRange

    Application.EnableEvents = True
    Application.Calculation = xlCalculationAutomatic
    Application.ScreenUpdating = True

    MsgBox "直前の実績反映を元に戻しました。"

End Sub


' ============================
' gBackupRowsに記録されている行を、反映前の値・フォント色に戻す（該当行が無ければ何もしない）
' ============================
Sub RevertBackedUpRows(ws As Worksheet, mapMainRange As Object)
    If gBackupRows Is Nothing Then Exit Sub
    If gBackupRows.Count = 0 Then Exit Sub

    Dim key As Variant
    For Each key In gBackupRows.Keys
        Dim foundRow As Long
        foundRow = key

        Dim rng As Range
        Set rng = ws.Range(mapMainRange("開始") & foundRow & ":" & mapMainRange("終了") & foundRow)

        Dim backupData As Variant
        backupData = gBackupRows(key)

        Dim oldVals As Variant, oldColors As Variant
        oldVals = backupData(0)
        oldColors = backupData(1)

        rng.Value = oldVals
        SetFontColors rng, oldColors
    Next key

    Set gBackupRows = Nothing
    Set gPendingReviewRows = Nothing
End Sub


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
Sub MarkUnmatchedActualRows(ws As Worksheet, mapMainCol As Object, mapMainRange As Object, matchedRows As Object, backupRows As Object, lastRow As Long, ByRef unmatchedCount As Long, ByRef unmatchedRows As String)
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

                ' グレーにする前の値・フォント色をバックアップしておく（元に戻すため）
                If Not backupRows.Exists(r) Then
                    backupRows(r) = Array(rng.Value, GetFontColors(rng))
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

    If gDuplicateHighlightBackup Is Nothing Then
        Set gDuplicateHighlightBackup = CreateObject("Scripting.Dictionary")
    End If

    If lastRow < 5 Then
        Set BuildMainIndex = dic
        Exit Function
    End If

    Dim colYear As Variant, colCase As Variant, colQ As Variant, colR As Variant, colYojitsu As Variant
    colYear = mapMainCol("年度")
    colCase = mapMainCol("案件ID")
    colQ = mapMainCol("会計区分1")
    colR = mapMainCol("会計区分2")
    colYojitsu = mapMainCol("予実")

    Dim years As Variant, caseIds As Variant, qs As Variant, rs As Variant, yojitsus As Variant
    years = ws.Range(ws.Cells(1, colYear), ws.Cells(lastRow, colYear)).Value
    caseIds = ws.Range(ws.Cells(1, colCase), ws.Cells(lastRow, colCase)).Value
    qs = ws.Range(ws.Cells(1, colQ), ws.Cells(lastRow, colQ)).Value
    rs = ws.Range(ws.Cells(1, colR), ws.Cells(lastRow, colR)).Value
    yojitsus = ws.Range(ws.Cells(1, colYojitsu), ws.Cells(lastRow, colYojitsu)).Value

    Dim rowsByKey As Object
    Set rowsByKey = CreateObject("Scripting.Dictionary")   ' キー → 該当行番号（カンマ区切り文字列）

    Dim r As Long
    For r = 5 To lastRow
        If yojitsus(r, 1) = "実績" _
                And Trim(years(r, 1) & "") <> "" _
                And Trim(caseIds(r, 1) & "") <> "" _
                And Trim(qs(r, 1) & "") <> "" _
                And Trim(rs(r, 1) & "") <> "" Then
            Dim k As String
            k = years(r, 1) & "|" & caseIds(r, 1) & "|" & qs(r, 1) & "|" & rs(r, 1)

            If rowsByKey.Exists(k) Then
                rowsByKey(k) = rowsByKey(k) & ", " & r
            Else
                rowsByKey(k) = CStr(r)
            End If

            If Not dic.Exists(k) Then dic(k) = r
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
                        ws.Cells(dupRow, colQ).Font.Color, _
                        ws.Cells(dupRow, colR).Font.Color)
                End If

                ws.Cells(dupRow, colYear).Font.Color = groupColor
                ws.Cells(dupRow, colCase).Font.Color = groupColor
                ws.Cells(dupRow, colQ).Font.Color = groupColor
                ws.Cells(dupRow, colR).Font.Color = groupColor
            Next p

            colorIdx = colorIdx + 1
        End If
    Next key

    If msg <> "" Then
        Err.Raise vbObjectError + 1001, _
                  "BuildMainIndex", _
                  MAIN_SHEET_NAME & "に、条件（年度・案件ID・会計区分1・会計区分2）が重複する行があります。" & vbCrLf & vbCrLf & _
                  msg & _
                  "実績反映を行う前に、" & MAIN_SHEET_NAME & "側の重複を解消してください。"
    End If

    Set BuildMainIndex = dic
End Function


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
    If gPendingReviewRows Is Nothing Then Exit Sub
    If Sh.Name <> MAIN_SHEET_NAME Then Exit Sub

    If Not gPasteRangeCached Then
        Dim mapMainRange As Object
        Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")
        gPasteRangeStartCol = Sh.Range(mapMainRange("開始") & "1").Column
        gPasteRangeEndCol = Sh.Range(mapMainRange("終了") & "1").Column
        gPasteRangeCached = True
    End If

    If Target.Column < gPasteRangeStartCol Or Target.Column > gPasteRangeEndCol Then Exit Sub
    If Not gPendingReviewRows.Exists(Target.Row) Then Exit Sub

    Dim info As Variant
    info = gPendingReviewRows(Target.Row)

    Dim rowOldVals As Variant, rowNewVals As Variant
    rowOldVals = info(0)
    rowNewVals = info(1)

    Dim colIdx As Long
    colIdx = Target.Column - gPasteRangeStartCol + 1

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
' 指定ヘッダーの「下方向2列」を辞書に読み込む
' ============================
Function LoadMappingHorizontal(headerText As String) As Object
    Dim dic As Object
    Set dic = CreateObject("Scripting.Dictionary")

    Dim ws As Worksheet
    Set ws = ThisWorkbook.Sheets("システム用")

    Dim lastCol As Long
    lastCol = ws.Cells(5, ws.Columns.Count).End(xlToLeft).Column

    Dim c As Long
    Dim found As Boolean

    ' 5行目の横方向を走査してヘッダーを探す
    For c = 1 To lastCol
        If ws.Cells(5, c).Value = headerText Then
            found = True

            Dim r As Long
            r = 6 ' マッピングは6行目から始まる

            ' 空行に当たるまで読み込む
            Do While ws.Cells(r, c).Value <> ""
                Dim key As String
                Dim val As String

                key = ws.Cells(r, c).Value
                val = ws.Cells(r, c + 1).Value ' 右隣の列が値

                If key <> "" Then dic(key) = val

                r = r + 1
            Loop

            Exit For
        End If
    Next c

    ' ★ ヘッダーが見つからなかった場合は強制終了
    If Not found Then
        Err.Raise vbObjectError + 1000, _
                  "LoadMappingHorizontal", _
                  "ヘッダー「" & headerText & "」が見つかりません。"
    End If

    Set LoadMappingHorizontal = dic
End Function
