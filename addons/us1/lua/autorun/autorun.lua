if CLIENT then

include('client/client.lua')


end




if SERVER then


AddCSLuaFile('client/client.lua')
include('server/server.lua')


end