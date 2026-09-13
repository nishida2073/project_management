Option Explicit

Private Sub Workbook_Open()
    HandleWorkbookOpen
End Sub


Private Sub Workbook_BeforeSave(ByVal SaveAsUI As Boolean, Cancel As Boolean)
    HandleBeforeSave
End Sub


Private Sub Workbook_BeforeClose(Cancel As Boolean)
    HandleBeforeClose
End Sub


Private Sub Workbook_SheetBeforeDoubleClick(ByVal Sh As Object, ByVal Target As Range, Cancel As Boolean)
    HandleSheetBeforeDoubleClick Sh, Target, Cancel
End Sub
