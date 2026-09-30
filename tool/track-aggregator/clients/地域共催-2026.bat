@echo off

set "KintoneLoginName=user01"
set "KintonePassword=abcd1234"
set "KintoneSubdomain=iiglepv0966f"
set "Authorization="
set "BaseUrl=https://%KintoneSubdomain%.cybozu.com"

set "SpaceId=7"
set "ThreadId=9"
set "MentionUserCodes="
set "CommentTextTemplate=集計結果を更新しました。（{TargetGroupName}）"

set "PassScore=100"

set "SyncUserMasterAppId=14"
set "SyncUserMasterSheetName=受講生一覧"

if not defined KintoneSubdomain set "KintoneSubdomain=iiglepv0966f"
if not defined KintoneLoginName set "KintoneLoginName=user01"
if not defined KintonePassword set "KintonePassword=abcd1234"
if not defined Authorization set "Authorization="
if not defined BaseUrl set "BaseUrl=https://%KintoneSubdomain%.cybozu.com"
if not defined ThreadId set "ThreadId=9"
if not defined MentionUserCodes set "MentionUserCodes="
if not defined SpaceId set "SpaceId=7"
if not defined CommentTextTemplate set "CommentTextTemplate=集計結果を更新しました。（{TargetGroupName}）"
if not defined PassScore set "PassScore=100"
if not defined YearOrder set "YearOrder="
if not defined ComparePeriod set "ComparePeriod="
if not defined SyncUserMasterAppId set "SyncUserMasterAppId=14"
if not defined SyncUserMasterSheetName set "SyncUserMasterSheetName=受講生一覧"
