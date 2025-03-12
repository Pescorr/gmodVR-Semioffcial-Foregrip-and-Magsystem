-- VRMod Physgun System Module
-- このファイルは、複数のPhysgunシステムを独立して稼働させるためのモジュールです

-- グローバル変数の初期化
g_VR = g_VR or {}
vrmod = vrmod or {}

-- モジュール作成関数
function CreateVRPhysgunSystem(prefix)
    local physgunmaxrange = GetConVar("physgun_maxrange")

    -- エンティティの登録
    scripted_ents.Register({Type = "anim"}, "vrmod_physgun_controller_" .. prefix)
    
    if CLIENT then
        -- ビーム描画用のマテリアル
        local beam_mat1 = Material("sprites/physbeam")
        local beam_mat2 = Material("sprites/physbeama")
        local beam_glow1 = Material("sprites/physg_glow1")
        local beam_glow2 = Material("sprites/physg_glow2")
        
        -- ビーム設定用のConVar
        CreateClientConVar("vrmod_" .. prefix .. "_physgun_beam_enable", "1", true, FCVAR_ARCHIVE, "PhysgunビームをON/OFFする")
        CreateClientConVar("vrmod_" .. prefix .. "_physgun_beam_range", physgunmaxrange:GetFloat(), true, FCVAR_ARCHIVE, "Physgunビームの最大距離")
        CreateClientConVar("vrmod_" .. prefix .. "_physgun_beam_color_a", "0", true, FCVAR_ARCHIVE, "Physgunビームのアルファ成分")

        -- ビームダメージ用のConVar
        CreateClientConVar("vrmod_" .. prefix .. "_physgun_beam_damage", "0.0001", true, FCVAR_ARCHIVE, "ビームのダメージ量", 0, 1.000)
        CreateClientConVar("vrmod_" .. prefix .. "_physgun_beam_damage_enable", "1", true, FCVAR_ARCHIVE, "ビームダメージの有効/無効")        
        
        -- 引き寄せ機能用のConVar
        CreateClientConVar("vrmod_" .. prefix .. "_physgun_pull_enable", "1", true, FCVAR_ARCHIVE, "オブジェクト引き寄せ機能の有効/無効")
        
        -- 掴んでいるエンティティの参照
        g_VR["physgunHeldEntity_" .. prefix] = nil
        
        -- 掴む/放す操作の送信関数
        vrmod["PhysgunAction_" .. prefix] = function(bDrop)
            -- モジュールが無効の場合は処理しない
            if GetConVar("vrmod_" .. prefix .. "_physgun_beam_enable"):GetInt() == 0 then
                return
            end
            
            net.Start("vrmod_physgun_action_" .. prefix)
            net.WriteBool(bDrop or false)
            
            local hand = prefix == "left" and "pose_lefthand" or "pose_righthand"
            local pose = g_VR.tracking[hand]
            net.WriteVector(pose.pos)
            net.WriteAngle(pose.ang)
            
            if bDrop then
                net.WriteVector(pose.vel)
                net.WriteVector(pose.angvel)
                g_VR["physgunHeldEntity_" .. prefix] = nil
            end
            
            net.SendToServer()
        end
        
        -- オブジェクト引き寄せ関数
        vrmod["PhysgunPull_" .. prefix] = function()
            -- 引き寄せ機能が無効の場合は処理しない
            if not GetConVar("vrmod_" .. prefix .. "_physgun_pull_enable"):GetBool() then return end
            
            -- 持っているエンティティをチェック
            local heldEntity = g_VR["physgunHeldEntity_" .. prefix]
            if not heldEntity or not IsValid(heldEntity) then return end
            
            net.Start("vrmod_physgun_pull_" .. prefix)
            net.SendToServer()
            
            -- プル効果音
            if IsValid(heldEntity) then
                heldEntity:EmitSound("weapons/physgun_off.wav")
            end
        end
        
        -- PhysgunビームのRGB値を取得
        local function GetPhysgunBeamColor()
            -- デフォルトの色を設定
            local r, g, b = 0, 255, 255 -- デフォルトの水色
            local a = GetConVar("vrmod_" .. prefix .. "_physgun_beam_color_a"):GetInt()
            
            -- 正しく存在する場合のみConVarから取得
            local r_cvar = GetConVar("physgun_color_r")
            local g_cvar = GetConVar("physgun_color_g")
            local b_cvar = GetConVar("physgun_color_b")
            
            if r_cvar then r = r_cvar:GetInt() end
            if g_cvar then g = g_cvar:GetInt() end
            if b_cvar then b = b_cvar:GetInt() end
            
            -- 色がなければweaponcolorから取得を試みる
            if r == 0 and g == 255 and b == 255 then
                local weaponColor = GetConVar("cl_weaponcolor")
                if weaponColor then
                    local colorStr = weaponColor:GetString()
                    local parts = string.Split(colorStr, " ")
                    if #parts >= 3 then
                        r = tonumber(parts[1]) * 255
                        g = tonumber(parts[2]) * 255
                        b = tonumber(parts[3]) * 255
                    end
                end
            end
            
            return Color(r, g, b, a)
        end
        
        -- ビーム描画関数
        local function DrawPhysgunBeams()
            if not g_VR.active then return end
            
            -- ビームが無効の場合は描画しない
            if not GetConVar("vrmod_" .. prefix .. "_physgun_beam_enable"):GetBool() then return end
            
            local beamColor = GetPhysgunBeamColor()
            local hand = prefix == "left" and "pose_lefthand" or "pose_righthand"
            local heldEnt = g_VR["physgunHeldEntity_" .. prefix]
            
            local startPos = g_VR.tracking[hand].pos
            local forward = g_VR.tracking[hand].ang:Forward()
            local beamRange = GetConVar("vrmod_" .. prefix .. "_physgun_beam_range"):GetFloat()
            
            -- トレースして終点を検出
            local tr = util.TraceLine({
                start = startPos,
                endpos = startPos + forward * beamRange,
                filter = LocalPlayer()
            })
            
            -- 終点を決定
            local endPos
            if heldEnt and IsValid(heldEnt) then
                endPos = heldEnt:GetPos()
            else
                endPos = tr.HitPos
            end
            
            -- ビームカラー
            local color = beamColor
            if heldEnt and IsValid(heldEnt) then
                -- 掴んでいる場合は色を少し明るくする
                color = Color(
                    math.min(color.r + 50, 255),
                    math.min(color.g + 50, 255), 
                    math.min(color.b + 50, 255), 
                    color.a
                )
            end
            
            -- メインビーム描画
            render.SetMaterial(beam_mat1)
            render.DrawBeam(startPos, endPos, 2, 0, 1, color)
            
            -- 二次ビーム描画
            render.SetMaterial(beam_mat2)
            render.DrawBeam(startPos, endPos, 1, 0, 1, Color(color.r, color.g, color.b, color.a * 0.5))
            
            -- 発光エフェクト描画
            render.SetMaterial(beam_glow1)
            local size = math.random(15, 25)
            render.DrawSprite(startPos, size, size, color)
            
            local endSize = heldEnt and IsValid(heldEnt) and math.random(8, 12) or math.random(3, 6)
            render.DrawSprite(endPos, endSize, endSize, color)
            
            -- ダメージ処理
            -- エンティティを持ち上げている場合はダメージ処理をスキップ
            if GetConVar("vrmod_" .. prefix .. "_physgun_beam_damage_enable"):GetBool() and tr.Hit and IsValid(tr.Entity) and not heldEnt then
                if tr.Entity:GetClass() == "prop_ragdoll" then
                    local damage = GetConVar("vrmod_" .. prefix .. "_physgun_beam_damage"):GetFloat()
                    -- ダメージ送信
                    net.Start("vrmod_physgun_beam_damage_" .. prefix)
                    net.WriteVector(tr.HitPos)
                    net.WriteFloat(damage)
                    net.SendToServer()
                end
            end
        end
        
        -- ビーム描画用フック追加
        hook.Add("PostDrawTranslucentRenderables", "vrmod_physgun_beams_" .. prefix, function(depth, sky)
            if depth or sky then return end
            DrawPhysgunBeams()
        end)
        
        -- ネットワークメッセージ受信処理
        net.Receive("vrmod_physgun_action_" .. prefix, function(len)
            local ply = net.ReadEntity()
            local ent = net.ReadEntity()
            local bDrop = net.ReadBool()
            
            if bDrop then
                -- ドロップ時の処理
                if IsValid(ent) and ent.RenderOverride == ent["VRPhysgunRenderOverride_" .. prefix] then
                    ent.RenderOverride = nil
                end
                
                -- 自分自身の場合は参照を削除
                if ply == LocalPlayer() then
                    if g_VR["physgunHeldEntity_" .. prefix] == ent then
                        g_VR["physgunHeldEntity_" .. prefix] = nil
                    end
                end
                
                -- ドロップサウンド
                if IsValid(ent) then
                    ent:EmitSound("physics/metal/metal_box_impact_soft" .. math.random(1, 3) .. ".wav")
                end
            else
                -- ピックアップ時の処理
                local localPos = net.ReadVector()
                local localAng = net.ReadAngle()
                local steamid = IsValid(ply) and ply:SteamID()
                
                if g_VR.net[steamid] == nil then return end
                
                -- RenderOverrideを設定
                ent.RenderOverride = function()
                    if g_VR.net[steamid] == nil then return end
                    
                    local wpos, wang
                    local hand = prefix == "left" and "lefthand" or "righthand"
                    wpos, wang = LocalToWorld(localPos, localAng, g_VR.net[steamid].lerpedFrame[hand .. "Pos"], g_VR.net[steamid].lerpedFrame[hand .. "Ang"])
                    
                    ent:SetPos(wpos)
                    ent:SetAngles(wang)
                    ent:SetupBones()
                    ent:DrawModel()
                end
                
                ent["VRPhysgunRenderOverride_" .. prefix] = ent.RenderOverride
                
                -- 自分自身の場合は参照を保存
                if ply == LocalPlayer() then
                    g_VR["physgunHeldEntity_" .. prefix] = ent
                end
                
                -- ピックアップサウンド
                ent:EmitSound("weapons/physgun_on.wav")
            end
        end)
        
    elseif SERVER then
        util.AddNetworkString("vrmod_physgun_action_" .. prefix)
        util.AddNetworkString("vrmod_physgun_beam_damage_" .. prefix)
        util.AddNetworkString("vrmod_physgun_pull_" .. prefix)
        
        -- Physgunコントローラー設定
        local PhysgunController = {
            controller = nil,
            pickupList = {},
            pickupCount = 0
        }
        
        -- Physics shadow パラメータ
        local ShadowParams = {
            secondstoarrive = 0.0001,
            maxangular = 5000,
            maxangulardamp = 5000,
            maxspeed = 5000,
            maxspeeddamp = 10000,
            dampfactor = 0.5,
            teleportdistance = 0,
            deltatime = 0
        }
        
        -- ビームダメージ受信処理
        net.Receive("vrmod_physgun_beam_damage_" .. prefix, function(len, ply)
            if not IsValid(ply) or ply:InVehicle() then return end
            if not ply:GetInfoNum("vrmod_" .. prefix .. "_physgun_beam_damage_enable", 1) == 1 then return end
            
            local hitPos = net.ReadVector()
            local damage = net.ReadFloat()
            
            -- ダメージ情報を構築
            local dmgInfo = DamageInfo()
            dmgInfo:SetAttacker(ply)
            dmgInfo:SetInflictor(ply)
            dmgInfo:SetDamage(damage)
            dmgInfo:SetDamageType(DMG_CRUSH)
            dmgInfo:SetDamagePosition(hitPos)
            
            -- 範囲ダメージを適用
            util.BlastDamageInfo(dmgInfo, hitPos, 3.0)
        end)
        
        -- 引き寄せ機能受信処理
        net.Receive("vrmod_physgun_pull_" .. prefix, function(len, ply)
            if not IsValid(ply) or ply:InVehicle() then return end
            
            -- プレイヤーのPickupリストから持っているアイテムを特定
            for i = 1, PhysgunController.pickupCount do
                local t = PhysgunController.pickupList[i]
                if t.steamid ~= ply:SteamID() then continue end
                
                -- エンティティの位置を手元に調整
                local frame = g_VR[ply:SteamID()].latestFrame
                if not frame then continue end
                
                -- 手の位置を取得
                local handPos, handAng
                if prefix == "left" then
                    handPos, handAng = LocalToWorld(frame.lefthandPos, frame.lefthandAng, ply:GetPos(), Angle())
                else
                    handPos, handAng = LocalToWorld(frame.righthandPos, frame.righthandAng, ply:GetPos(), Angle())
                end
                
                -- 手の正面20cm前に引き寄せる
                local newLocalPos = Vector(-5, 0, 0) -- 手の前10cm
                t.localPos = newLocalPos
                
                -- 引き寄せイベント
                hook.Run("VRPhysgun_Pull_" .. prefix, ply, t.ent)
                
                -- 引き寄せられたことを通知
                ply:EmitSound("physics/metal/metal_box_strain" .. math.random(1, 3) .. ".wav")
                break
            end
        end)
        
        -- エンティティドロップ関数
        local function drop(steamid, handPos, handAng, handVel, handAngVel)
            for i = 1, PhysgunController.pickupCount do
                local t = PhysgunController.pickupList[i]
                if t.steamid ~= steamid then continue end
                
                local phys = t.phys
                if IsValid(phys) then
                    t.ent:SetCollisionGroup(t.collisionGroup)
                    PhysgunController.controller:RemoveFromMotionController(phys)
                    
                    if handPos then
                        local wPos, wAng = LocalToWorld(t.localPos, t.localAng, handPos, handAng)
                        phys:SetPos(wPos)
                        phys:SetAngles(wAng)
                        phys:SetVelocity(t.ply:GetVelocity() + handVel)
                        phys:AddAngleVelocity(-phys:GetAngleVelocity() + phys:WorldToLocalVector(handAngVel))
                        phys:Wake()
                    end
                end
                
                -- ドロップ情報をクライアントに送信
                net.Start("vrmod_physgun_action_" .. prefix)
                net.WriteEntity(t.ply)
                net.WriteEntity(t.ent)
                net.WriteBool(true) -- drop
                net.Broadcast()
                
                -- グローバルテーブルのクリーンアップ
                if g_VR[t.steamid] then
                    g_VR[t.steamid]["physgunHeldItems_" .. prefix] = g_VR[t.steamid]["physgunHeldItems_" .. prefix] or {}
                    g_VR[t.steamid]["physgunHeldItems_" .. prefix] = nil
                end
                
                -- リストからアイテムを削除
                PhysgunController.pickupList[i] = PhysgunController.pickupList[PhysgunController.pickupCount]
                PhysgunController.pickupList[PhysgunController.pickupCount] = nil
                PhysgunController.pickupCount = PhysgunController.pickupCount - 1
                
                -- 持っているアイテムがなくなったらコントローラーを削除
                if PhysgunController.pickupCount == 0 and IsValid(PhysgunController.controller) then
                    PhysgunController.controller:StopMotionController()
                    PhysgunController.controller:Remove()
                    PhysgunController.controller = nil
                end
                
                -- ドロップイベント
                hook.Run("VRPhysgun_Drop_" .. prefix, t.ply, t.ent)
                
                return
            end
        end
        
        -- エンティティピックアップ関数
        local function pickup(ply, handPos, handAng)
            local steamid = ply:SteamID()
            
            -- トレース範囲
            local maxRange = ply:GetInfoNum("vrmod_" .. prefix .. "_physgun_beam_range", physgunmaxrange:GetFloat())

            -- 手の方向にトレース
            local tr = util.TraceLine({
                start = handPos,
                endpos = handPos + handAng:Forward() * maxRange,
                filter = ply
            })
            
            -- ヒットしなかった場合
            if not tr.Hit or not IsValid(tr.Entity) then return end
            
            local entity = tr.Entity
            
            -- 無効なエンティティをフィルタリング
            if entity:IsPlayer() 
            or  not IsValid(entity:GetPhysicsObject()) 
            or ply:InVehicle() 
            or entity:GetMoveType() ~= MOVETYPE_VPHYSICS 
            or entity:GetPhysicsObject():GetMass() > 1000
            or (entity.CPPICanPickup and not entity:CPPICanPickup(ply))
            then
                return
            end
            
            -- カスタムフックによるピックアップの可否確認
            if hook.Run("VRPhysgun_CanPickup_" .. prefix, ply, entity) == false then 
                return 
            end
            
            -- コントローラーの初期化
            if not IsValid(PhysgunController.controller) then
                PhysgunController.controller = ents.Create("vrmod_physgun_controller_" .. prefix)
                PhysgunController.controller.ShadowParams = table.Copy(ShadowParams)
                
                function PhysgunController.controller:PhysicsSimulate(phys, deltatime)
                    phys:Wake()
                    local t = phys:GetEntity()["vrmod_physgun_info_" .. prefix]
                    local frame = g_VR[t.steamid] and g_VR[t.steamid].latestFrame
                    
                    if not frame then return end
                    
                    local handPos, handAng
                    if prefix == "left" then
                        handPos, handAng = LocalToWorld(frame.lefthandPos, frame.lefthandAng, t.ply:GetPos(), Angle())
                    else
                        handPos, handAng = LocalToWorld(frame.righthandPos, frame.righthandAng, t.ply:GetPos(), Angle())
                    end
                    
                    self.ShadowParams.pos, self.ShadowParams.angle = LocalToWorld(t.localPos, t.localAng, handPos, handAng)
                    phys:ComputeShadowControl(self.ShadowParams)
                end
                
                PhysgunController.controller:StartMotionController()
                
                -- Tickフックを追加
                if not hook.GetTable()["Tick"]["vrmod_physgun_tick_" .. prefix] then
                    hook.Add("Tick", "vrmod_physgun_tick_" .. prefix, function()
                        for i = 1, PhysgunController.pickupCount do
                            local t = PhysgunController.pickupList[i]
                            if not IsValid(t.phys) or 
                            not t.phys:IsMoveable() or 
                            not g_VR[t.steamid] or 
                            not t.ply:Alive() or 
                            t.ply:InVehicle() then
                                drop(t.steamid)
                            end
                        end
                    end)
                end
            end
            
            -- エンティティが既にこの手で持たれているかチェック
            for k = 1, PhysgunController.pickupCount do
                if PhysgunController.pickupList[k].ent == entity then return end -- 既に持っている
            end
            
            -- エンティティの持っている状態チェック (他のシステムで持たれていないか)
            if entity.RenderOverride then
                -- 既に他のシステムに持たれている可能性がある
                local otherPrefix = prefix == "left" and "right" or "left"
                if entity["VRPhysgunRenderOverride_" .. otherPrefix] then
                    -- 他方のシステムで持たれているので、処理しない
                    return 
                end
            end
            
            -- 物理オブジェクト取得
            local phys = entity:GetPhysicsObject()
            
            -- ローカル座標計算
            local localPos, localAng = WorldToLocal(entity:GetPos(), entity:GetAngles(), handPos, handAng)
            
            -- 物理オブジェクトを起動、コントローラーに追加
            phys:Wake()
            PhysgunController.pickupCount = PhysgunController.pickupCount + 1
            local index = PhysgunController.pickupCount
            PhysgunController.controller:AddToMotionController(phys)
            
            -- ピックアップ情報を保存
            PhysgunController.pickupList[index] = {
                ent = entity,
                phys = phys,
                localPos = localPos,
                localAng = localAng,
                collisionGroup = entity:GetCollisionGroup(),
                steamid = steamid,
                ply = ply
            }
            
            -- グローバルテーブルに追加
            g_VR[steamid] = g_VR[steamid] or {}
            g_VR[steamid]["physgunHeldItems_" .. prefix] = PhysgunController.pickupList[index]
            
            -- エンティティに参照を保存
            entity["vrmod_physgun_info_" .. prefix] = PhysgunController.pickupList[index]
            
            -- 衝突グループを設定
            entity:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR)
            
            -- クライアントにピックアップ情報を送信
            net.Start("vrmod_physgun_action_" .. prefix)
            net.WriteEntity(ply)
            net.WriteEntity(entity)
            net.WriteBool(false) -- not drop
            net.WriteVector(localPos)
            net.WriteAngle(localAng)
            net.Broadcast()
            
            -- ピックアップイベント
            hook.Run("VRPhysgun_Pickup_" .. prefix, ply, entity)
        end
        
        -- ネットワークメッセージ受信
        net.Receive("vrmod_physgun_action_" .. prefix, function(len, ply)
            if not IsValid(ply) or not g_VR[ply:SteamID()] then return end
            
            -- クライアント側のモジュール有効設定をチェック
            if ply:GetInfoNum("vrmod_" .. prefix .. "_physgun_beam_enable", 1) == 0 then
                return
            end
            
            local bDrop = net.ReadBool()
            
            if not bDrop then
                pickup(ply, net.ReadVector(), net.ReadAngle())
            else
                drop(ply:SteamID(), net.ReadVector(), net.ReadAngle(), net.ReadVector(), net.ReadVector())
            end
        end)
    end

    -- 入力処理フック (右手と左手で別々の入力処理)
    hook.Add(
        "VRMod_Input",
        "vrmod_physgun_input_" .. prefix,
        function(action, pressed)
            -- モジュールが無効の場合は処理しない
            if CLIENT and GetConVar("vrmod_" .. prefix .. "_physgun_beam_enable"):GetInt() == 0 then return end
            
            local activationAction = "boolean_" .. (prefix == "left" and "left_primaryfire" or "primaryfire")
            local pickupAction = "boolean_" .. prefix .. "_pickup"
            
            if action == activationAction then
                vrmod["PhysgunAction_" .. prefix](not pressed)
            elseif CLIENT and pressed and action == pickupAction then
                vrmod["PhysgunPull_" .. prefix]()
            end
        end
    )

    -- メニュー項目の追加
    hook.Add("VRMod_Menu", "vrmod_physgun_menu_" .. prefix, function(frame)
        local form = frame.SettingsForm
        
        -- 設定セクション作成
        local panel = vgui.Create("DPanel")
        panel:SetSize(390, 220)
        panel:SetBackgroundColor(Color(0, 0, 0, 0))
        
        -- タイトル
        local title = vgui.Create("DLabel", panel)
        title:SetText("VR Physgun Settings (" .. string.upper(prefix) .. " HAND)")
        title:SetFont("DermaDefaultBold")
        title:SetTextColor(Color(0, 0, 0))
        title:SetPos(5, 5)
        title:SizeToContents()
        
        -- ビーム有効/無効
        local enableBeam = vgui.Create("DCheckBoxLabel", panel)
        enableBeam:SetText("Enable Physgun Beams")
        enableBeam:SetConVar("vrmod_" .. prefix .. "_physgun_beam_enable")
        enableBeam:SetPos(10, 25)
        enableBeam:SizeToContents()
        
        -- ビーム距離
        local beamRange = vgui.Create("DNumSlider", panel)
        beamRange:SetText("Beam Range")
        beamRange:SetMin(10)
        beamRange:SetMax(physgunmaxrange:GetFloat())
        beamRange:SetDecimals(0)
        beamRange:SetConVar("vrmod_" .. prefix .. "_physgun_beam_range")
        beamRange:SetPos(10, 45)
        beamRange:SetSize(350, 20)
        
        -- ビーム色 - Alpha
        local colorA = vgui.Create("DNumSlider", panel)
        colorA:SetText("Beam Alpha")
        colorA:SetMin(0)
        colorA:SetMax(255)
        colorA:SetDecimals(0)
        colorA:SetConVar("vrmod_" .. prefix .. "_physgun_beam_color_a")
        colorA:SetPos(10, 65)
        colorA:SetSize(350, 20)
        
        -- ダメージ有効/無効
        local enableDamage = vgui.Create("DCheckBoxLabel", panel)
        enableDamage:SetText("Enable Beam Damage")
        enableDamage:SetConVar("vrmod_" .. prefix .. "_physgun_beam_damage_enable")
        enableDamage:SetPos(10, 95)
        enableDamage:SizeToContents()
        
        -- ダメージ量
        local damageAmount = vgui.Create("DNumSlider", panel)
        damageAmount:SetText("Beam Damage Amount")
        damageAmount:SetMin(0.0001)
        damageAmount:SetMax(0.0100)
        damageAmount:SetDecimals(4)
        damageAmount:SetConVar("vrmod_" .. prefix .. "_physgun_beam_damage")
        damageAmount:SetPos(10, 115)
        damageAmount:SetSize(350, 20)
        
        -- 引き寄せ機能有効/無効
        local enablePull = vgui.Create("DCheckBoxLabel", panel)
        enablePull:SetText("Enable Pull Feature (Grip Button)")
        enablePull:SetConVar("vrmod_" .. prefix .. "_physgun_pull_enable")
        enablePull:SetPos(10, 145)
        enablePull:SizeToContents()
        
        -- 使い方説明
        local instructions = vgui.Create("DLabel", panel)
        instructions:SetText("Use the " .. prefix .. " hand trigger to grab objects and grip button to pull them closer")
        instructions:SetTextColor(Color(0, 0, 0))
        instructions:SetPos(10, 170)
        instructions:SetSize(350, 40)
        instructions:SetWrap(true)
        
        form:AddItem(panel)
    end)

    -- 初期化完了メッセージ
    print("[VRMod] " .. string.upper(prefix) .. " hand Physgun controller module loaded")
end

-- 左手と右手のシステムを作成
CreateVRPhysgunSystem("left")
CreateVRPhysgunSystem("right")

print("[VRMod] Dual Physgun systems initialized")