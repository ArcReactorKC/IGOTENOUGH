local mq = require('mq')
local imgui = require('ImGui')

-- TODO: add option to announce to different channels
local state = {
    itemList = {},
    selectedIndex = 1,
    selectedItem = "",
    threshold = 1,
    monitoring = false,
    announced = false,
    doScan = false,
}

local running = true

mq.bind("/stopia", function()
    print("InventoryAnnouncer stopping...")
    running = false
end)

local function scanItemContents(item, found, items)
    for i = 0, 9 do
        local subitem = item.Item(i)
        if subitem() and subitem.Name() and subitem.Name() ~= "" then
            local name = subitem.Name()
            if not found[name] then
                table.insert(items, name)
                found[name] = true
            end
            -- recursive call for nested containers
            scanItemContents(subitem, found, items)
        end
    end
end

local function scanInventory()
    print("Running inventory scan...")
    local me = mq.TLO.Me
    if not me() then
        print("Character not ready!")
        return
    end

    local found = {}
    local items = {}

    -- scan all inventory slots
    for slot = 0, 31 do
        local item = me.Inventory(slot)
        if item() and item.Name() and item.Name() ~= "" then
            local name = item.Name()
            if not found[name] then
                table.insert(items, name)
                found[name] = true
            end
            scanItemContents(item, found, items)
        end
    end

    table.sort(items)
    state.itemList = items
    if #items > 0 then
        state.selectedIndex = 1
        state.selectedItem = items[1]
    else
        state.selectedIndex = 0
        state.selectedItem = ""
    end
    state.announced = false
    print("Scan complete. Found " .. #items .. " unique items.")
end

local function countItemInItem(item, itemName)
    local total = 0
    for i = 0, 9 do
        local subitem = item.Item(i)
        if subitem() and subitem.Name() then
            if subitem.Name() == itemName then
                local stackSize = subitem.Stack()
                if stackSize and stackSize > 0 then
                    total = total + stackSize
                else
                    total = total + 1
                end
            end
            total = total + countItemInItem(subitem, itemName)
        end
    end
    return total
end

local function getItemCount(itemName)
    if not itemName or itemName == "" then return 0 end
    local total = 0
    local me = mq.TLO.Me

    for slot = 0, 31 do
        local item = me.Inventory(slot)
        if item() and item.Name() then
            if item.Name() == itemName then
                local stackSize = item.Stack()
                if stackSize and stackSize > 0 then
                    total = total + stackSize
                else
                    total = total + 1
                end
            end
            total = total + countItemInItem(item, itemName)
        end
    end

    return total
end

mq.imgui.init("InventoryAnnouncerUI", function()
    ImGui.Begin("Inventory Announcer")

    if ImGui.Button("X Close") then
        print("InventoryAnnouncer closing via UI...")
        running = false
    end
    ImGui.SameLine()
    
    if ImGui.Button("Scan Inventory") then
        state.doScan = true
    end

    if state.doScan then
        ImGui.Text("Scanning inventory...")
    end

    if #state.itemList > 0 then
        ImGui.Text("Select Item:")
        ImGui.BeginChild("ItemList", 0, 100, true)
        for i, itemName in ipairs(state.itemList) do
            local selected = (i == state.selectedIndex)
            if ImGui.Selectable(itemName, selected) and state.selectedIndex ~= i then
                state.selectedIndex = i
                state.selectedItem = itemName
                state.announced = false
                print("Selected item: " .. itemName)
            end
        end
        ImGui.EndChild()

        ImGui.Text("Threshold: " .. state.threshold)
        
        if ImGui.Button("-") then
            if state.threshold > 1 then
                state.threshold = state.threshold - 1
                state.announced = false
                print("Threshold decreased to: " .. state.threshold)
            end
        end
        ImGui.SameLine()
        if ImGui.Button("+") then
            state.threshold = state.threshold + 1
            state.announced = false
            print("Threshold increased to: " .. state.threshold)
        end

        if ImGui.Button(state.monitoring and "Stop Monitoring" or "Start Monitoring") then
            state.monitoring = not state.monitoring
            state.announced = false
            if state.monitoring then
                print("Started monitoring " .. state.selectedItem .. " (threshold: " .. state.threshold .. ")")
            else
                print("Stopped monitoring")
            end
        end

        local count = getItemCount(state.selectedItem)
        ImGui.Text(string.format("Current Count: %d / Threshold: %d", count, state.threshold))

        if state.announced then
            ImGui.TextColored(0, 1, 0, 1, "Announced to group.")
        end
    else
        ImGui.Text("Click 'Scan Inventory' to populate item list.")
    end

    ImGui.End()
end)

print("InventoryAnnouncer started. Use /stopia to stop.")

while running do
    if state.doScan then
        scanInventory()
        state.doScan = false
    end

    if state.monitoring and state.selectedItem and state.selectedItem ~= "" and not state.announced then
        local count = getItemCount(state.selectedItem)
        if count >= state.threshold then
            mq.cmdf("/g I now have %d %s!", count, state.selectedItem)
            state.announced = true
            print("Announced to group: " .. count .. " " .. state.selectedItem)
        end
    end

    mq.delay(1000)
end

print("InventoryAnnouncer stopped.")