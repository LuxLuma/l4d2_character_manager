#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required

#define PLUGIN_VERSION "1.0.5"

//ABM https://forums.alliedmods.net/showthread.php?p=2477820
//don't use with abm's cvar enabled (abm_identityfix 1)

//Identity fix https://forums.alliedmods.net/showthread.php?t=280539
//Don't use identity fix with this plugin

static char sModelTracking[MAXPLAYERS+1][PLATFORM_MAX_PATH];

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if(GetEngineVersion() != Engine_Left4Dead2 )
	{
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2");
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public Plugin myinfo =
{
	name = "[L4D2]Character_manager",
	author = "Lux",
	description = "Sets bots to least used survivor character when spawned from(0-7)",
	version = PLUGIN_VERSION,
	url = "https://forums.alliedmods.net/showthread.php?p=2607394"
};

public void OnPluginStart()
{
	CreateConVar("l4d2_character_manager_version", PLUGIN_VERSION, "l4d2_character_manager_version", FCVAR_DONTRECORD|FCVAR_NOTIFY);
	HookEvent("bot_player_replace", eBotToPlayer, EventHookMode_Post);
	HookEvent("player_bot_replace", ePlayerToBot, EventHookMode_Post);
	HookEvent("round_start", eRoundEnd, EventHookMode_Pre);
}

public void eRoundEnd(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	for(int i = 0; i <= MaxClients; i++)
		sModelTracking[i][0] = '\0';
}

//credit for some of meurdo identity fix code
static char sSurvivorNames[9][] = { "Nick", "Rochelle", "Coach", "Ellis", "Bill", "Zoey", "Francis", "Louis", "AdaWong"};
static char sSurvivorModels[9][] =
{
	"models/survivors/survivor_gambler.mdl",
	"models/survivors/survivor_producer.mdl",
	"models/survivors/survivor_coach.mdl",
	"models/survivors/survivor_mechanic.mdl",
	"models/survivors/survivor_namvet.mdl",
	"models/survivors/survivor_teenangst.mdl",
	"models/survivors/survivor_biker.mdl",
	"models/survivors/survivor_manager.mdl",
	"models/survivors/survivor_adawong.mdl"
};

public void eBotToPlayer(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "player"));
	if(iClient < 1 || !IsClientInGame(iClient) || GetClientTeam(iClient) != 2 || IsFakeClient(iClient)) 
		return;
	
	int iBot = GetClientOfUserId(GetEventInt(hEvent, "bot"));
	if(iBot < 1 || !IsClientInGame(iBot) || GetClientTeam(iClient) != 2)
		return;
	
	SetEntProp(iClient, Prop_Send, "m_survivorCharacter", GetEntProp(iBot, Prop_Send, "m_survivorCharacter", 2), 2);
	char sModel[PLATFORM_MAX_PATH];
	GetEntPropString(iBot, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
	SetEntityModel(iClient, sModel);
}

public void ePlayerToBot(Handle hEvent, const char[] sName, bool bDontBroadcast)
{
	int iBot = GetClientOfUserId(GetEventInt(hEvent, "bot"));
	if(iBot < 1 || !IsClientInGame(iBot) || GetClientTeam(iBot) != 2)
		return;
	
	int iClient = GetClientOfUserId(GetEventInt(hEvent, "player"));
	if(iClient < 1 || !IsClientInGame(iClient) || IsFakeClient(iClient) || GetClientTeam(iClient) != 2 || sModelTracking[iClient][0] == '\0') 
	{
		SetCharacter(iBot);
		return;
	}
	
	SetEntProp(iBot, Prop_Send, "m_survivorCharacter", GetEntProp(iClient, Prop_Send, "m_survivorCharacter"));
	SetEntityModel(iBot, sModelTracking[iClient]);
	
	if(!StrContains(sModelTracking[8], "survivor_adawong", false))
	{
		for (int i = 0; i < 7; i++)
			if (StrEqual(sModelTracking[iClient], sSurvivorModels[i])) 
				SetClientInfo(iBot, "name", sSurvivorNames[i]);
	}
	else
		SetClientInfo(iBot, "name", sSurvivorNames[8]);
}

public void OnGameFrame()
{
	static int i;
	for(i = 1;i <= MaxClients;i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i))
			continue;
		
		if(GetClientTeam(i) != 2) 
		{
			sModelTracking[i][0] = '\0' ;
			continue;
		}
		
		static int iModelIndex[MAXPLAYERS+1] = {0, ...};
		if(iModelIndex[i] == GetEntProp(i, Prop_Data, "m_nModelIndex", 2))
			continue;
		
		static char sModel[PLATFORM_MAX_PATH];
		GetEntPropString(i, Prop_Data, "m_ModelName", sModel, sizeof(sModel));
		strcopy(sModelTracking[i], PLATFORM_MAX_PATH, sModel);
	}
}

public void OnEntityCreated(int iEntity, const char[] sClassname)
{
	if(sClassname[0] != 's' || !StrEqual(sClassname, "survivor_bot"))
	 	return;
	 
	SDKHook(iEntity, SDKHook_SpawnPost, SpawnPost);
}

public void SpawnPost(int iEntity)
{
	if(!IsValidEntity(iEntity) || !IsFakeClient(iEntity))
		return;	
	
	if(GetClientTeam(iEntity) == 4)
		return;
	
	SetCharacter(iEntity);
	RequestFrame(NextFrame, GetClientUserId(iEntity));
}

public void NextFrame(int iUserID)
{
	int iClient = GetClientOfUserId(iUserID);
	
	if(iClient < 1 || !IsClientInGame(iClient))
		return;
	
	SetCharacter(iClient);
}

//set iclient to 0 to not ignore, for anyone using this function
int CheckLeastUsedSurvivor(int iClient)
{
	int iLeastChar[8];
	int iCharBuffer;
	int i;
	for(i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || GetClientTeam(i) != 2 || i == iClient)
			continue;
		
		if((iCharBuffer = GetEntProp(i, Prop_Send, "m_survivorCharacter", 2)) > 7)//in SpawnPost the entprop is 8, because valve wants it to be 8 at this point
			continue;
		
		iLeastChar[iCharBuffer]++;
	}
	
	int iSurvivorCharIndex = iLeastChar[0];
	iCharBuffer = 0;
	
	for(i = 0; i <= 7; i++)
	{
		if(iLeastChar[i] < iSurvivorCharIndex)
		{
			iSurvivorCharIndex = iLeastChar[i];
			iCharBuffer = i;
		}
	}
	
	return iCharBuffer;
}

void SetCharacter(int iClient)
{
	int iCharSet = CheckLeastUsedSurvivor(iClient);
	SetEntProp(iClient, Prop_Send, "m_survivorCharacter", iCharSet, 2);
	SetEntityModel(iClient, sSurvivorModels[iCharSet]);
	SetClientInfo(iClient, "name", sSurvivorNames[iCharSet]);
}