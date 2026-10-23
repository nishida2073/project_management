@echo off

set "KintoneSubdomain=iiglepv0966f"
set "KintoneLoginName=user01"
set "KintonePassword=wrong-password"
set "KintoneBaseUrl=https://%KintoneSubdomain%.cybozu.com"
set "ThreadId=230"
set "SpaceId=3"
set "CommentTextTemplate=集計結果を更新しました。（{グループ名} / {対象日}）"
set "CommentSummaryTemplate=■ クラス名 : {クラス名}\n・業務日誌（未提出）: {業務日誌未提出人数}\n・パルスサーベイ（未提出）: {パルスサーベイ未提出人数}\n・アラート: {アラート人数}"
set "SyncUserMasterAppId="
set "PulseTargetAppIds=181"
set "DailyTargetAppIds=180"
set "MentionUserCodes="
