@echo off

set "KintoneLoginName="
set "KintonePassword="
set "Authorization="
set "KintoneSubdomain=univ-kyousai-{x}"
set "BaseUrl=https://%KintoneSubdomain%.cybozu.com"

set "SpaceId="
set "ThreadId="
set "MentionUserCodes="
set "CommentTextTemplate=アラート結果を更新しました。（{TargetGroupName} / {TargetDate}）"

set "TargetAppIds_Daily="

set "TargetAppIds_Pulse="

set "SyncUserMasterAppId="
set "SyncUserMasterSheetName=受講生一覧"