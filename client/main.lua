local Zone = nil
local TextShown = false
local AcitveZone = {}
local CurrentVehicle = {}
local SpawnZone = {}
local EntityZones = {}
local occasionVehicles = {}

-- Functions

local function spawnOccasionsVehicles(vehicles)
    if Zone then
        local oSlot = Config.Zones[Zone].VehicleSpots
        if not occasionVehicles[Zone] then occasionVehicles[Zone] = {} end
        if vehicles then
            for i = 1, #vehicles, 1 do
                local model = GetHashKey(vehicles[i].model)
                RequestModel(model)
                while not HasModelLoaded(model) do
                    Wait(0)
                end
                occasionVehicles[Zone][i] = {
                    car   = CreateVehicle(model, oSlot[i].x, oSlot[i].y, oSlot[i].z, false, false),
                    loc   = vector3(oSlot[i].x, oSlot[i].y, oSlot[i].z),
                    price = vehicles[i].price,
                    owner = vehicles[i].seller,
                    model = vehicles[i].model,
                    plate = vehicles[i].plate,
                    oid   = vehicles[i].occasionid,
                    desc  = vehicles[i].description,
                    mods  = vehicles[i].mods
                }

                lib.setVehicleProperties(occasionVehicles[Zone][i].car, json.decode(vehicles[i].mods))

                SetModelAsNoLongerNeeded(model)
                SetVehicleOnGroundProperly(occasionVehicles[Zone][i].car)
                SetEntityInvincible(occasionVehicles[Zone][i].car,true)
                SetEntityHeading(occasionVehicles[Zone][i].car, oSlot[i].w)
                SetVehicleDoorsLocked(occasionVehicles[Zone][i].car, 3)
                SetVehicleNumberPlateText(occasionVehicles[Zone][i].car, occasionVehicles[Zone][i].oid)
                FreezeEntityPosition(occasionVehicles[Zone][i].car,true)
                if Config.UseTarget then
                    if not EntityZones then EntityZones = {} end
                    EntityZones[i] = exports['qb-target']:AddTargetEntity(occasionVehicles[Zone][i].car, {
                        options = {
                            {
                                type = "client",
                                event = "qb-vehiclesales:client:OpenContract",
                                icon = "fas fa-car",
                                label = Lang:t("menu.view_contract"),
                                Contract = i
                            }
                        },
                        distance = 2.0
                    })
                end
            end
        end
    end
end

local function despawnOccasionsVehicles()
    if not Zone then return end
    local oSlot = Config.Zones[Zone].VehicleSpots
    for i = 1, #oSlot, 1 do
        local loc = oSlot[i]
        local oldVehicle = GetClosestVehicle(loc.x, loc.y, loc.z, 1.3, 0, 70)
        if oldVehicle then
            DeleteVehicle(oldVehicle)
        end

        if EntityZones[i] and Config.UseTarget then
            exports['qb-target']:RemoveZone(EntityZones[i])
        end
    end
    EntityZones = {}
end

local function openSellContract(bool)
    SetNuiFocus(bool, bool)
    SendNUIMessage({
        action = "sellVehicle",
        showTakeBackOption = false,
        bizName = Config.Zones[Zone].BusinessName,
        sellerData = {
            firstname = QBX.PlayerData.charinfo.firstname,
            lastname = QBX.PlayerData.charinfo.lastname,
            account = QBX.PlayerData.charinfo.account,
            phone = QBX.PlayerData.charinfo.phone
        },
        plate = GetPlate(cache.vehicle)
    })
end

local function openBuyContract(sellerData, vehicleData)
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = "buyVehicle",
        showTakeBackOption = sellerData.charinfo.firstname == QBX.PlayerData.charinfo.firstname and sellerData.charinfo.lastname == QBX.PlayerData.charinfo.lastname,
        bizName = Config.Zones[Zone].BusinessName,
        sellerData = {
            firstname = sellerData.charinfo.firstname,
            lastname = sellerData.charinfo.lastname,
            account = sellerData.charinfo.account,
            phone = sellerData.charinfo.phone
        },
        vehicleData = {
            desc = vehicleData.desc,
            price = vehicleData.price
        },
        plate = vehicleData.plate
    })
end

local function sellVehicleWait(price)
    DoScreenFadeOut(250)
    Wait(250)
    DeleteVehicle(cache.vehicle)
    Wait(1500)
    DoScreenFadeIn(250)
    exports.qbx_core:Notify(Lang:t('success.car_up_for_sale', { value = price }), 'success')
    PlaySound(-1, "SELECT", "HUD_FRONTEND_DEFAULT_SOUNDSET", false, 0, true)
end

local function SellData(data, model)
    lib.callback("qb-vehiclesales:server:CheckModelName", false, function(DataReturning)
        local vehicleData = {}
        vehicleData.ent = cache.vehicle
        vehicleData.model = DataReturning
        vehicleData.plate = model
        vehicleData.mods = lib.getVehicleProperties(vehicleData.ent)
        vehicleData.desc = data.desc
        TriggerServerEvent('qb-occasions:server:sellVehicle', data.price, vehicleData)
        sellVehicleWait(data.price)
    end, model)
end

local listen = false
local function Listen4Control(spot) -- Uses this to listen for controls to open various menus.
    listen = true
    CreateThread(function()
        while listen do
            if IsControlJustReleased(0, 38) then -- E
                if spot then
                    local data = {Contract = spot}
                    TriggerEvent('qb-vehiclesales:client:OpenContract', data)
                else
                    if IsPedInAnyVehicle(cache.ped, false) then
                        listen = false
                        TriggerEvent('qb-occasions:client:MainMenu')
                        --TriggerEvent('qb-vehiclesales:client:SellVehicle')
                    else
                        exports.qbx_core:Notify(Lang:t("error.not_in_veh"), "error", 4500)
                    end
                end
            end
            Wait(0)
        end
    end)
end

---- ** Main Zone Functions ** ----

local function CreateZones()
    for k, v in pairs(Config.Zones) do
        local SellSpot = PolyZone:Create(v.PolyZone, {
            name = k,
            minZ = 	v.MinZ,
            maxZ = v.MaxZ,
            debugPoly = false
        })

        SellSpot:onPlayerInOut(function(isPointInside)
            if isPointInside and Zone ~= k then
                Zone = k
                lib.callback('qb-occasions:server:getVehicles', false, function(vehicles)
                    despawnOccasionsVehicles()
                    spawnOccasionsVehicles(vehicles)
                end)
            else
                despawnOccasionsVehicles()
                Zone = nil
            end
        end)
        AcitveZone[k] = SellSpot
    end
end

local function DeleteZones()
    for k in pairs(AcitveZone) do
        AcitveZone[k]:destroy()
    end
    AcitveZone = {}
end

local function IsCarSpawned(Car)
    local bool = false

    if occasionVehicles then
        for k in pairs(occasionVehicles[Zone]) do
            if k == Car then
                bool = true
                break
            end
        end
    end
    return bool
end

-- NUI Callbacks

RegisterNUICallback('sellVehicle', function(data, cb)
    local plate = GetPlate(cache.vehicle) --Getting the plate and sending to the function
    SellData(data,plate)
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    SetNuiFocus(false, false)
    cb('ok')
end)

RegisterNUICallback('buyVehicle', function(_, cb)
    TriggerServerEvent('qb-occasions:server:buyVehicle', CurrentVehicle)
    cb('ok')
end)

RegisterNUICallback('takeVehicleBack', function(_, cb)
    TriggerServerEvent('qb-occasions:server:ReturnVehicle', CurrentVehicle)
    cb('ok')
end)

RegisterNetEvent('qb-occasions:client:BuyFinished', function(vehdata)
    DoScreenFadeOut(250)
    Wait(500)
    local veh = lib.callback.await('qbx_vehiclesales:server:spawnVehicle', false, vehdata, Config.Zones[Zone].BuyVehicle, false)
    local timeout = 100
    while not NetworkDoesEntityExistWithNetworkId(netId) and timeout > 0 do
        Wait(10)
        timeout -= 1
    end
    SetEntityHeading(veh, Config.Zones[Zone].BuyVehicle.w)
    SetVehicleFuelLevel(veh, 100)
    exports.qbx_core:Notify(Lang:t('success.vehicle_bought'), "success", 2500)
    Wait(500)
    DoScreenFadeIn(250)
    CurrentVehicle = {}
end)

RegisterNetEvent('qb-occasions:client:SellBackCar', function()
    if cache.vehicle then
        local vehicleData = {}
        vehicleData.model = GetEntityModel(cache.vehicle)
        vehicleData.plate = GetVehicleNumberPlateText(cache.vehicle)
        local owned, balance = lib.callback.await('qb-garage:server:checkVehicleOwner', false, vehicleData.plate)
        if owned then
            if balance < 1 then
                TriggerServerEvent('qb-occasions:server:sellVehicleBack', vehicleData)
                DeleteVehicle(cache.vehicle)
            else
                exports.qbx_core:Notify(Lang:t('error.finish_payments'), 'error', 3500)
            end
        else
            exports.qbx_core:Notify(Lang:t('error.not_your_vehicle'), 'error', 3500)
        end
    else
        exports.qbx_core:Notify(Lang:t("error.not_in_veh"), "error", 4500)
    end
end)

RegisterNetEvent('qb-occasions:client:ReturnOwnedVehicle', function(vehdata)
    DoScreenFadeOut(250)
    Wait(500)
    local veh = lib.callback.await('qbx_vehiclesales:server:spawnVehicle', false, vehdata, Config.Zones[Zone].BuyVehicle, false)
    local timeout = 100
    while not NetworkDoesEntityExistWithNetworkId(netId) and timeout > 0 do
        Wait(10)
        timeout -= 1
    end
    SetEntityHeading(veh, Config.Zones[Zone].BuyVehicle.w)
    SetVehicleFuelLevel(veh, 100)
    exports.qbx_core:Notify(Lang:t('success.vehicle_bought'), "success", 2500)
    Wait(500)
    DoScreenFadeIn(250)
    CurrentVehicle = {}
end)

RegisterNetEvent('qb-occasion:client:refreshVehicles', function()
    if Zone then
        local vehicles = lib.callback.await('qb-occasions:server:getVehicles')
        despawnOccasionsVehicles()
        spawnOccasionsVehicles(vehicles)
    end
end)

RegisterNetEvent('qb-vehiclesales:client:SellVehicle', function()
    local VehiclePlate = GetPlate(cache.vehicle)
    local owned, balance = lib.callback.await('qb-garage:server:checkVehicleOwner', false, VehiclePlate)
    if owned then
        if balance < 1 then
            lib.callback('qb-occasions:server:getVehicles', false, function(vehicles)
                if vehicles == nil or #vehicles < #Config.Zones[Zone].VehicleSpots then
                    openSellContract(true)
                else
                    exports.qbx_core:Notify(Lang:t('error.no_space_on_lot'), 'error', 3500)
                end
            end)
        else
            exports.qbx_core:Notify(Lang:t('error.finish_payments'), 'error', 3500)
        end
    else
        exports.qbx_core:Notify(Lang:t('error.not_your_vehicle'), 'error', 3500)
    end
end)

RegisterNetEvent('qb-vehiclesales:client:OpenContract', function(data)
    CurrentVehicle = occasionVehicles[Zone][data.Contract]
    if not CurrentVehicle then
        exports.qbx_core:Notify(Lang:t("error.not_for_sale"), 'error', 7500)
        return
    end

    local info = lib.callback.await('qb-occasions:server:getSellerInformation', false, CurrentVehicle.owner)
    if info then
        info.charinfo = json.decode(info.charinfo)
    else
        info = {}
        info.charinfo = {
            firstname = Lang:t('charinfo.firstname'),
            lastname = Lang:t('charinfo.lastname'),
            account = Lang:t('charinfo.account'),
            phone = Lang:t('charinfo.phone')
        }
    end

    openBuyContract(info, CurrentVehicle)
end)

RegisterNetEvent('qb-occasions:client:MainMenu', function()
    lib.registerContext({
        id = 'qb_vehiclesales_menu',
        title = Config.Zones[Zone].BusinessName,
        options = {
            {
                title =  Lang:t("menu.sell_vehicle"),
                description = Lang:t("menu.sell_vehicle_help"),
                event = 'qb-vehiclesales:client:SellVehicle',
            },
            {
                title =  Lang:t("menu.sell_back"),
                description = Lang:t("menu.sell_back_help"),
                event = 'qb-occasions:client:SellBackCar',
            },
        },
    })
    lib.showContext('qb_vehiclesales_menu')
end)

-- Threads

CreateThread(function()
    for _, cars in pairs(Config.Zones) do
        local OccasionBlip = AddBlipForCoord(cars.SellVehicle.x, cars.SellVehicle.y, cars.SellVehicle.z)
        SetBlipSprite (OccasionBlip, 326)
        SetBlipDisplay(OccasionBlip, 4)
        SetBlipScale  (OccasionBlip, 0.75)
        SetBlipAsShortRange(OccasionBlip, true)
        SetBlipColour(OccasionBlip, 3)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentSubstringPlayerName(Lang:t('info.used_vehicle_lot'))
        EndTextCommandSetBlipName(OccasionBlip)
    end
end)

CreateThread(function()
    for k, cars in pairs(Config.Zones) do
        SpawnZone[k] = CircleZone:Create(vector3(cars.SellVehicle.x, cars.SellVehicle.y, cars.SellVehicle.z), 3.0, {
            name="OCSell"..k,
            debugPoly = false,
        })

        SpawnZone[k]:onPlayerInOut(function(isPointInside)
            if isPointInside and IsPedInAnyVehicle(cache.ped, false) then
                exports['qbx-core']:DrawText(Lang:t("menu.interaction"), 'left')
                TextShown = true
                Listen4Control()
            else
                listen = false
                if TextShown then
                    TextShown = false
                    exports['qbx-core']:HideText()
                end
            end
        end)
        if not Config.UseTarget then
            for k2, v in pairs(Config.Zones[k].VehicleSpots) do
                local VehicleZones = BoxZone:Create(vector3(v.x, v.y, v.z), 4.3, 3.6, {
                    name="VehicleSpot"..k..k2,
                    debugPoly = false,
                    minZ = v.z-2,
                    maxZ = v.z+2,
                })
                VehicleZones:onPlayerInOut(function(isPointInside)
                    if isPointInside and IsCarSpawned(k2) then
                        exports['qbx-core']:DrawText(Lang:t("menu.view_contract_int"), 'left')
                        TextShown = true
                        Listen4Control(k2)
                    else
                        listen = false
                        if TextShown then
                            TextShown = false
                            exports['qbx-core']:HideText()
                        end
                    end
                end)
            end
        end
    end
end)

---- ** Mostly just to ensure you can restart resources live without issues, also improves the code slightly. ** ----

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    CreateZones()
end)

RegisterNetEvent('QBCore:Client:OnPlayerUnload', function()
    DeleteZones()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        CreateZones()
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() == resourceName then
        DeleteZones()
        despawnOccasionsVehicles()
    end
end)
