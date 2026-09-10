Option Explicit

Private Sub Workbook_Open()

    Dim isBrowser As Boolean
    isBrowser = (Application.OperatingSystem = "")

    If isBrowser Then Exit Sub

    EnsureButtonsExist

    Dim wsMain As Worksheet
    Set wsMain = Sheets("計画算定シート")

    If wsMain.Visible = xlSheetVisible Then
        wsMain.Range("A1").Select
    End If

End Sub


Private Sub Workbook_BeforeSave(ByVal SaveAsUI As Boolean, Cancel As Boolean)

    Dim ws As Worksheet
    Set ws = Sheets("計画算定シート")
    Dim mapMainRange As Object

    ' ★ 貼り付け範囲の 5行目～最終行まで黒字化
    Set mapMainRange = LoadMappingHorizontal("原価管理Excel貼付範囲")

    Dim lastRow As Long
    lastRow = ws.Cells.SpecialCells(xlCellTypeLastCell).Row   ' Ctrl+Shift+End と同じ判定

    If lastRow >= 5 Then
        ws.Range(mapMainRange("開始") & "5:" & mapMainRange("終了") & lastRow).Font.Color = vbBlack
    End If

End Sub


Private Sub Workbook_BeforeClose(Cancel As Boolean)

    Dim wsMain As Worksheet
    Set wsMain = Sheets("計画算定シート")

    DeleteButtonIfExists wsMain, "MacroProcButton999"
    DeleteButtonIfExists wsMain, "UndoProcButton999"

    ' このあと「変更を保存しますか？」でキャンセルされ、閉じずに残る場合に備えて
    ' 少し後にボタンが残っているか確認・復元する処理を予約しておく
    Application.OnTime Now, "'" & ThisWorkbook.Name & "'!EnsureButtonsExist"

End Sub
