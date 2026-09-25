@echo off

set "KintoneLoginName="
set "KintonePassword="
set "Authorization="
set "KintoneSubdomain=univ-kyousai-{x}"
set "BaseUrl=https://%KintoneSubdomain%.cybozu.com"

set "SpaceId="
set "ThreadId="
set "MentionUserCodes="
set "CommentTextTemplate=アラートの内容が更新されました。({TargetGroupName})"

set "SyncUserMasterAppId="
set "SyncUserMasterSheetName=受講生一覧"