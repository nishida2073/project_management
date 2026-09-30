@echo off

if not defined KintoneLoginName set "KintoneLoginName="
if not defined KintonePassword set "KintonePassword="
if not defined Authorization set "Authorization="
if not defined KintoneSubdomain set "KintoneSubdomain=univ-kyousai-{x}"
if not defined BaseUrl set "BaseUrl=https://%KintoneSubdomain%.cybozu.com"

if not defined SpaceId set "SpaceId="
if not defined ThreadId set "ThreadId="
if not defined MentionUserCodes set "MentionUserCodes="
if not defined CommentTextTemplate set "CommentTextTemplate=アラートの内容が更新されました。({TargetGroupName})"

if not defined SyncUserMasterAppId set "SyncUserMasterAppId="
if not defined SyncUserMasterSheetName set "SyncUserMasterSheetName=受講生一覧"