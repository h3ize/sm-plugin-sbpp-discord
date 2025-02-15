#pragma semicolon 1

#undef REQUIRE_PLUGIN
#tryinclude <sourcebanspp>
#tryinclude <sourcebanschecker>
#tryinclude <sourcecomms>
#define REQUIRE_PLUGIN

#define PLUGIN_NAME "Sourcebans_Discord"
#define STEAM_API_CVAR "sbpp_steam_api"

#include <RelayHelper>
#include <calladmin>
#include <clients>
#include <colorvariables>
#include <discordWebhookAPI>
#include <sourcebanschecker>
#include <sourcemod>

#pragma newdecls required

Global_Stuffs g_Sbpp;

public Plugin myinfo =
{
	name 		= PLUGIN_NAME,
	author 		= ".Rushaway, Dolly, koen, Sarrus, heize",
	version 	= "1.0.1",
	description = "Send Sourcebans Punishments and CallAdmin notifications to Discord",
	url 		= "https://nide.gg, https://heizemod.us"
};

ConVar g_cvWebhookURL;
ConVar g_cvMention;
ConVar g_cvBotUsername;
ConVar g_cvEmbedCallColor;
ConVar g_cvHostname;
ConVar g_cvIP;
ConVar g_cvPort;

char g_szHostname[256];
char g_szIP[32];
char g_szPort[32];

bool g_bDebugging = false;

public void OnPluginStart() {
	g_Sbpp.enable 	= CreateConVar("sbpp_discord_enable", "1", "Toggle sourcebans notification system", _, true, 0.0, true, 1.0);
	g_Sbpp.webhook 	= CreateConVar("sbpp_discord", "", "The webhook URL of your Discord channel. (Sourcebans)", FCVAR_PROTECTED);
	g_Sbpp.website	= CreateConVar("sbpp_website", "", "Your sourcebans link", FCVAR_PROTECTED);
	g_cvWebhookURL      = CreateConVar("calladmin_discord_webhook", "", "The webhook to the Discord channel where you want calladmin messages to be sent.", FCVAR_PROTECTED);
	g_cvMention         = CreateConVar("calladmin_discord_mention", "@here", "Optional Discord mention to ping users when a calladmin is sent.");
	g_cvBotUsername     = CreateConVar("calladmin_discord_username", "CallAdmin", "Username of the bot");
	g_cvEmbedCallColor  = CreateConVar("calladmin_discord_call_embed_color", "0xff0000", "Color of the embed when a calladmin is made. Replace the usual '#' with '0x'.");
	g_cvIP              = CreateConVar("calladmin_discord_ip", "0.0.0.0", "Set your server IP here when auto detection is not working for you. (Use 0.0.0.0 to disable manual override)");
	g_cvHostname        = FindConVar("hostname");
	g_cvHostname.GetString(g_szHostname, sizeof g_szHostname);

	char szIP[32];
	g_cvIP.GetString(szIP, sizeof szIP);

	g_cvIP = FindConVar("ip");
	g_cvIP.GetString(g_szIP, sizeof g_szIP);
	if (StrEqual("0.0.0.0", g_szIP))
	{
		strcopy(g_szIP, sizeof g_szIP, szIP);
	}
	g_cvPort = FindConVar("hostport");
	g_cvPort.GetString(g_szPort, sizeof g_szPort);

	RelayHelper_PluginStart();
	AutoExecConfig(true, PLUGIN_NAME);

	RegAdminCmd("sm_calladmin_discordtest", CommandDiscordTest, ADMFLAG_ROOT, "Test the Discord announcement");

	/* Incase of a late load */
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i) || IsFakeClient(i) || IsClientSourceTV(i) || g_sClientAvatar[i][0]) {
			continue;
		}

		OnClientPostAdminCheck(i);
	}
}

public void OnClientPostAdminCheck(int client) {
	if(IsFakeClient(client) || IsClientSourceTV(client)) {
		return;
	}

	GetClientSteamAvatar(client);
}

public void OnClientDisconnect(int client) {
	g_sClientAvatar[client][0] = '\0';
}

#if defined _sourcebanspp_included
public void SBPP_OnBanPlayer(int admin, int target, int length, const char[] reason) {
	if(!g_Sbpp.enable.BoolValue) {
		return;
	}

	if(admin < 1) {
		return;
	}

	int bansNumber = 0;
	int commsNumber = 0;

	#if defined _sourcebanschecker_included
	bansNumber = SBPP_CheckerGetClientsBans(target);
	commsNumber = SBPP_CheckerGetClientsComms(target);
	bansNumber++;
	#endif

	SendDiscordMessage(g_Sbpp, Message_Type_Ban, admin, target, length, reason, bansNumber, commsNumber, _, g_sClientAvatar[target]);
	PrintToServer("[Sourcebans-Discord] Ban Player: Admin=%d, Target=%d, Length=%d, Reason=%s", admin, target, length, reason);
}
#endif

#if defined _sourcecomms_included
public void SourceComms_OnBlockAdded(int admin, int target, int length, int commType, char[] reason) {
	if(!g_Sbpp.enable.BoolValue) {
		return;
	}

	if(admin < 1) {
		return;
	}

	MessageType type = Message_Type_Ban;
	switch(commType) {
		case TYPE_MUTE: {
			type = Message_Type_Mute;
		}

		case TYPE_UNMUTE: {
			type = Message_Type_Unmute;
		}

		case TYPE_GAG: {
			type = Message_Type_Gag;
		}

		case TYPE_UNGAG: {
			type = Message_Type_Ungag;
		}
	}

	if(type == Message_Type_Ban) {
		return;
	}

	int bansNumber = 0;
	int commsNumber = 0;

	#if defined _sourcebanschecker_included
	bansNumber = SBPP_CheckerGetClientsBans(target);
	commsNumber = SBPP_CheckerGetClientsComms(target);
	commsNumber++;
	#endif

	SendDiscordMessage(g_Sbpp, type, admin, target, length, reason, bansNumber, commsNumber, _, g_sClientAvatar[target]);
	PrintToServer("[Sourcebans-Discord] Block Added: Admin=%d, Target=%d, Length=%d, CommType=%d, Reason=%s", admin, target, length, commType, reason);
}
#endif

public Action CommandDiscordTest(int client, int args)
{
    CPrintToChat(client, "{blue}[CallAdmin-Discord] Sending test message.");
    CallAdmin_OnReportPost(client, client, "This is the reason");
    CPrintToChat(client, "{blue}[CallAdmin-Discord] Test message sent.");
    return Plugin_Handled;
}

public void CallAdmin_OnReportPost(int iClient, int iTarget, const char[] szReason)
{
    char webhook[1024];
    GetConVarString(g_cvWebhookURL, webhook, sizeof webhook);
    if (StrEqual(webhook, ""))
    {
        PrintToServer("[CallAdmin-Discord] No webhook specified, aborting.");
        return;
    }
    Webhook hook = new Webhook();
    char szMention[128];
    GetConVarString(g_cvMention, szMention, sizeof szMention);
    if (!StrEqual(szMention, ""))
    {
        hook.SetContent(szMention);
    }
    char szCalladminName[64];
    GetConVarString(g_cvBotUsername, szCalladminName, sizeof szCalladminName);
    hook.SetUsername(szCalladminName);
    Embed embed = new Embed();
    char color[16];
    GetConVarString(g_cvEmbedCallColor, color, sizeof color);
    embed.SetColor(StringToInt(color, 16));
    char szTitle[256];
    Format(szTitle, sizeof szTitle, "CallAdmin - %s", szReason);
    embed.SetTitle(szTitle);
    char szClientID[256], szTargetID[256], szSteamClientID[64], szSteamTargetID[64], szNameClient[MAX_NAME_LENGTH], szNameTarget[MAX_NAME_LENGTH];
    GetClientName(iClient, szNameClient, sizeof szNameClient);
    GetClientAuthId(iClient, AuthId_SteamID64, szSteamClientID, sizeof szSteamClientID);
    Format(szClientID, sizeof szClientID, "[%s](https://steamcommunity.com/profiles/%s)", szNameClient, szSteamClientID);
    GetClientName(iTarget, szNameTarget, sizeof szNameTarget);
    GetClientAuthId(iTarget, AuthId_SteamID64, szSteamTargetID, sizeof szSteamTargetID);
    Format(szTargetID, sizeof szTargetID, "[%s](https://steamcommunity.com/profiles/%s)", szNameTarget, szSteamTargetID);
    EmbedField field = new EmbedField("Reporter", szClientID, true);
    embed.AddField(field);
    field = new EmbedField("Target", szTargetID, true);
    embed.AddField(field);
    char szServerInfo[256];
    Format(szServerInfo, sizeof szServerInfo, "**Connect IP: %s:%s**", g_szIP, g_szPort);
    field = new EmbedField("Connect IP", szServerInfo, false);
    embed.AddField(field);
    EmbedFooter footer = new EmbedFooter();
    char buffer[1000];
    Format(buffer, sizeof buffer, "%s", g_szHostname);
    footer.SetText(buffer);
    embed.SetFooter(footer);
    hook.AddEmbed(embed);
    if (g_bDebugging)
    {
        char szDebugOutput[10000];
        hook.ToString(szDebugOutput, sizeof szDebugOutput);
        PrintToServer(szDebugOutput);
    }
    hook.Execute(webhook, OnWebHookExecuted, iClient);
    delete hook;
}
