@echo off

if not defined KintoneLoginName set "KintoneLoginName="
if not defined KintonePassword set "KintonePassword="
if not defined Authorization set "Authorization="
if not defined KintoneSubdomain set "KintoneSubdomain=univ-kyousai-{x}"
if not defined BaseUrl set "BaseUrl=https://%KintoneSubdomain%.cybozu.com"

if not defined SpaceId set "SpaceId="
if not defined ThreadId set "ThreadId="
if not defined MentionUserCodes set "MentionUserCodes="
if not defined CommentTextTemplate set "CommentTextTemplate=アラート結果を更新しました。（{TargetGroupName} / {TargetDate}）"

if not defined TargetAppIds_Daily set "TargetAppIds_Daily="

if not defined TargetAppIds_Pulse set "TargetAppIds_Pulse="

if not defined SyncUserMasterAppId set "SyncUserMasterAppId="
if not defined SyncUserMasterSheetName set "SyncUserMasterSheetName=受講生一覧"