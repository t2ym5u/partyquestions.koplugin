-- ---------------------------------------------------------------------------
-- Party Questions deck logic (pure Lua, no UI -- testable headless)
--
-- All selected decks are shuffled into one pile; cards are drawn without
-- repeats until the pile is empty. Drawn cards are kept in a history, so
-- "Previous" can go back and "Next" replays forward before drawing again.
-- A "Hot seat" draw takes three hot-seat questions at once: one player
-- answers all three.
--
-- A card id is "<deck>:<f|a>:<index>" (family or adult list of that deck),
-- which keeps a saved game small and independent of the card text.
-- ---------------------------------------------------------------------------

local Deck = {}
Deck.__index = Deck

Deck.ORDER = {
    "wyr", "nhie", "mlt", "gtky", "hotseat", "dinner",
    "dilemmas", "debates", "thisorthat", "stories", "guesswho", "timemachine",
}
Deck.HOT_SEAT = "hotseat"
Deck.HOT_SEAT_SIZE = 3

function Deck.parseId(id)
    local deck, kind, idx = tostring(id):match("^(%w+):([fa]):(%d+)$")
    if not deck then return nil end
    return deck, kind, tonumber(idx)
end

-- cards: deck id -> { family = {...}, adult = {...} }
function Deck.text(cards, id)
    local deck, kind, idx = Deck.parseId(id)
    local d = deck and cards[deck]
    if not d then return nil end
    local list = kind == "a" and d.adult or d.family
    return list and list[idx]
end

-- opts: decks = { id = true, ... } (nil = all), adults = bool
function Deck.new(opts)
    opts = opts or {}
    return setmetatable({
        decks    = opts.decks,
        adults   = opts.adults and true or false,
        pile     = {},
        history  = {},
        pos      = 0,
        finished = false,
        total    = 0,
    }, Deck)
end

function Deck:isSelected(id)
    return self.decks == nil or self.decks[id] == true
end

-- Shuffles every selected card into a fresh pile.
function Deck:build(cards, rng)
    rng = rng or math.random
    local pile = {}
    for _, id in ipairs(Deck.ORDER) do
        local d = cards[id]
        if d and self:isSelected(id) then
            for i = 1, #(d.family or {}) do pile[#pile + 1] = id .. ":f:" .. i end
            if self.adults then
                for i = 1, #(d.adult or {}) do pile[#pile + 1] = id .. ":a:" .. i end
            end
        end
    end
    for i = #pile, 2, -1 do
        local j = rng(i)
        pile[i], pile[j] = pile[j], pile[i]
    end
    self.pile, self.history, self.pos, self.finished = pile, {}, 0, false
    self.total = #pile
    return #pile
end

local function deckOf(id)
    return (Deck.parseId(id))
end

-- Takes the top card; a hot-seat card brings two more hot-seat questions
-- with it (fewer if the pile runs out of them).
function Deck:_draw()
    local id = table.remove(self.pile)
    if not id then return nil end
    local entry = { id }
    if deckOf(id) == Deck.HOT_SEAT then
        for k = #self.pile, 1, -1 do
            if #entry >= Deck.HOT_SEAT_SIZE then break end
            if deckOf(self.pile[k]) == Deck.HOT_SEAT then
                entry[#entry + 1] = table.remove(self.pile, k)
            end
        end
    end
    return entry
end

-- Moves to the next card. Returns the entry, or nil once the deck is
-- exhausted (the game is then finished).
function Deck:next()
    if self.finished then return nil end
    if self.pos < #self.history then
        self.pos = self.pos + 1
        return self.history[self.pos]
    end
    local entry = self:_draw()
    if not entry then
        self.finished = true
        return nil
    end
    self.history[#self.history + 1] = entry
    self.pos = #self.history
    return entry
end

function Deck:prev()
    if self.finished then
        self.finished = false
    elseif self.pos > 1 then
        self.pos = self.pos - 1
    end
    return self.history[self.pos]
end

function Deck:canGoBack()
    return self.finished or self.pos > 1
end

function Deck:current()
    if self.finished then return nil end
    return self.history[self.pos]
end

function Deck:isFinished()
    return self.finished
end

-- Questions seen so far (a hot-seat draw counts three).
function Deck:cardsPlayed()
    return self.total - #self.pile
end

-- Which player's turn the current card is: the n-th draw goes to player
-- ((n - 1) mod count) + 1.
function Deck:turnIndex(count)
    if not count or count < 1 or self.pos < 1 then return nil end
    return (self.pos - 1) % count + 1
end

-- ---------------------------------------------------------------------------
-- Persistence
-- ---------------------------------------------------------------------------

function Deck:serialize()
    local decks
    if self.decks then
        decks = {}
        for id in pairs(self.decks) do decks[#decks + 1] = id end
        table.sort(decks)
    end
    local pile, history = {}, {}
    for i, id in ipairs(self.pile) do pile[i] = id end
    for i, e in ipairs(self.history) do
        history[i] = table.concat(e, ",")
    end
    return {
        decks = decks, adults = self.adults, pile = pile,
        history = history, pos = self.pos, finished = self.finished, total = self.total,
    }
end

-- `cards` (optional) validates every id against the loaded content, so a
-- save made with an older, longer deck file can't point at missing text.
function Deck.load(data, cards)
    if type(data) ~= "table" or type(data.pile) ~= "table" or type(data.history) ~= "table" then
        return nil
    end
    local decks
    if type(data.decks) == "table" then
        decks = {}
        for _, id in ipairs(data.decks) do decks[id] = true end
    end
    local self = Deck.new{ decks = decks, adults = data.adults }
    local function ok(id)
        return Deck.parseId(id) and (not cards or Deck.text(cards, id) ~= nil)
    end
    for _, id in ipairs(data.pile) do
        if not ok(id) then return nil end
        self.pile[#self.pile + 1] = id
    end
    for _, s in ipairs(data.history) do
        local e = {}
        for id in tostring(s):gmatch("[^,]+") do
            if not ok(id) then return nil end
            e[#e + 1] = id
        end
        self.history[#self.history + 1] = e
    end
    self.pos      = math.max(0, math.min(tonumber(data.pos) or 0, #self.history))
    self.finished = data.finished and true or false
    local n = 0
    for _, e in ipairs(self.history) do n = n + #e end
    self.total = math.max(tonumber(data.total) or 0, #self.pile + n)
    return self
end

return Deck
