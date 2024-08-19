AddCSLuaFile()

function vrmod_advanced_magazine()
    if CLIENT then
        -- 新しいConVarの作成
        CreateClientConVar("vrmod_mag_ejectbone_enable", "0", true, false, "Enable/Disable magazine eject bone functionality")

        -- グローバル変数の初期化
        local magazineState = 0 -- 0: デフォルト, 1: マガジン非表示, 2: マガジンをVR左手に持っている
        local magazineBones = {"mag", "clip"} -- マガジンとして認識するボーン名
        local hiddenBones = {}
        local heldBoneIndex = nil
        local isHolding = false
        local isPickingUpSomething = false
        local canPickupMagazine = true
        local lastMagazineReleaseTime = 0
        local hasLeftMagazineArea = false

        -- 機能が有効かどうかをチェックする関数
        local function IsFeatureEnabled()
            return GetConVar("vrmod_mag_ejectbone_enable"):GetBool()
        end

        -- ボーン名がマガジン関連かどうかをチェックする関数
        local function IsMagazineBone(boneName)
            boneName = string.lower(boneName)
            for _, name in ipairs(magazineBones) do
                if string.find(boneName, name, 1, true) then return true end
            end
            return false
        end

        -- マガジン関連のボーンを非表示にする関数
        local function HideMagazineBones(viewModel)
            for i = 0, viewModel:GetBoneCount() - 1 do
                local boneName = viewModel:GetBoneName(i)
                if IsMagazineBone(boneName) then
                    viewModel:ManipulateBoneScale(i, Vector(0, 0, 0))
                    hiddenBones[i] = true
                end
            end
        end

        -- マガジン関連のボーンを表示する関数
        local function ShowMagazineBones(viewModel)
            for i, _ in pairs(hiddenBones) do
                viewModel:ManipulateBoneScale(i, Vector(1, 1, 1))
            end
            hiddenBones = {}
        end

        -- 機能をリセットする関数
        local function ResetFeature(viewModel)
            magazineState = 0
            ShowMagazineBones(viewModel)
            heldBoneIndex = nil
            isHolding = false
            isPickingUpSomething = false
            canPickupMagazine = true
            lastMagazineReleaseTime = 0
            hasLeftMagazineArea = false
        end

        -- VRの描画前に実行されるフック
        hook.Add("VRMod_PreRender", "VRAdvancedMagazineInteraction", function()
            if not g_VR.active or not IsFeatureEnabled() then return end
            local ply = LocalPlayer()
            local weapon = ply:GetActiveWeapon()
            local viewModel = ply:GetViewModel()

            if not IsValid(weapon) or not IsValid(viewModel) then
                ResetFeature(viewModel)
                return
            end

            local leftHandPos = g_VR.tracking.pose_lefthand.pos
            local leftHandAng = g_VR.tracking.pose_lefthand.ang

            -- マガジンエリアにいるかどうかのチェック
            local inMagazineArea = false
            for i = 0, viewModel:GetBoneCount() - 1 do
                local boneName = viewModel:GetBoneName(i)
                if IsMagazineBone(boneName) then
                    local bonePos = viewModel:GetBonePosition(i)
                    if bonePos:DistToSqr(leftHandPos) < 40 then
                        inMagazineArea = true
                        break
                    end
                end
            end

            if not inMagazineArea then
                hasLeftMagazineArea = true
            end

            -- canPickupMagazineの更新
            if (hasLeftMagazineArea and inMagazineArea) or (CurTime() - lastMagazineReleaseTime > 1.2) then
                canPickupMagazine = true
            end

            -- 状態に応じた処理
            if magazineState == 0 then -- デフォルト状態
                -- 左手がマガジンに近づいたかチェック
                for i = 0, viewModel:GetBoneCount() - 1 do
                    local boneName = viewModel:GetBoneName(i)
                    if IsMagazineBone(boneName) then
                        local bonePos = viewModel:GetBonePosition(i)
                        if bonePos:DistToSqr(leftHandPos) > 200  and isHolding and canPickupMagazine then -- 距離のしきい値を調整
                            magazineState = 2
                            HideMagazineBones(viewModel)
                            heldBoneIndex = i
                            break
                        end
                    end
                end
            elseif magazineState == 1 then -- マガジン非表示状態
                if isPickingUpSomething then
                    magazineState = 2
                    -- 最も近いマガジンボーンを特定
                    local closestBone = nil
                    local closestDist = math.huge
                    for i = 0, viewModel:GetBoneCount() - 1 do
                        local boneName = viewModel:GetBoneName(i)
                        if IsMagazineBone(boneName) then
                            local bonePos = viewModel:GetBonePosition(i)
                            local dist = bonePos:DistToSqr(leftHandPos)
                            if dist < closestDist then
                                closestBone = i
                                closestDist = dist
                            end
                        end
                    end
                    heldBoneIndex = closestBone
                end
            elseif magazineState == 2 then -- マガジンを左手に持っている状態
                if not isHolding and not isPickingUpSomething then
                    magazineState = 1
                    -- heldBoneIndex = nil
                elseif isPickingUpSomething then
                    -- マガジンをビューモデルのボーンに近づけたかチェック
                    for i = 0, viewModel:GetBoneCount() - 1 do
                        local boneName = viewModel:GetBoneName(i)
                        if IsMagazineBone(boneName) then
                            local bonePos = viewModel:GetBonePosition(i)
                            if bonePos:DistToSqr(leftHandPos) < 40 then -- 距離のしきい値を調整
                                magazineState = 0
                                ShowMagazineBones(viewModel)
                                heldBoneIndex = nil
                                canPickupMagazine = false
                                lastMagazineReleaseTime = CurTime()
                                hasLeftMagazineArea = false
                                break
                            end
                        end
                    end
                end

                -- マガジンを左手の位置に移動
                if heldBoneIndex then
                    local boneMatrix = viewModel:GetBoneMatrix(heldBoneIndex)
                    if boneMatrix then
                        boneMatrix:SetTranslation(leftHandPos)
                        boneMatrix:SetAngles(leftHandAng)
                        viewModel:SetBoneMatrix(heldBoneIndex, boneMatrix)
                    end
                end
            end
        end)

        -- 左手のピックアップ入力を処理するフック
        hook.Add("VRMod_Input", "VRAdvancedMagazinePickup", function(action, pressed)
            if not IsFeatureEnabled() then return end
            if action == "boolean_left_pickup" then
                isHolding = pressed
                if not pressed then
                    isPickingUpSomething = false -- ボタンが離されたら何も持っていない状態にする
                end
            end
        end)

        -- 何かをピックアップしたときの処理
        hook.Add("VRMod_Pickup", "VRAdvancedMagazinePickupSomething", function(player, entity)
            if not IsFeatureEnabled() then return end
            if player == LocalPlayer() then
                isPickingUpSomething = true
            end
        end)

        -- マガジンの状態をリセットするコンソールコマンド
        concommand.Add("vrmod_magazine_reset", function()
            local viewModel = LocalPlayer():GetViewModel()
            if IsValid(viewModel) then
                ResetFeature(viewModel)
            end
        end)

        -- ConVarが変更されたときの処理
        cvars.AddChangeCallback("vrmod_mag_ejectbone_enable", function(convar_name, value_old, value_new)
            local viewModel = LocalPlayer():GetViewModel()
            if IsValid(viewModel) then
                if value_new == "0" then
                    ResetFeature(viewModel)
                end
            end
        end)
    end
end

vrmod_advanced_magazine()