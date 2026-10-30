-- busted spec for the Party Questions deck logic and content.
-- Run from the plugin dir: busted test_deck_spec.lua
local Deck = dofile("deck.lua")

local function loadCards(lang)
    local all = {}
    for _, id in ipairs(Deck.ORDER) do all[id] = dofile("cards/" .. lang .. "/" .. id .. ".lua") end
    return all
end

-- Names that must never appear in the cards: figures mainly known for
-- genocide, terrorism, mass murder or dictatorship, serial killers, and
-- living politicians. Whole words, lower case, accents stripped.
local EXCLUDED = {
    "hitler", "nazi", "nazis", "staline", "stalin", "pol pot", "ben laden", "bin laden",
    "mussolini", "mao zedong", "pinochet", "kim jong", "saddam", "kadhafi", "gaddafi",
    "idi amin", "attila", "gengis khan", "genghis khan", "landru", "eventreur", "ripper",
    "ceausescu", "himmler", "goebbels", "macron", "sarkozy", "hollande", "trump", "biden",
    "poutine", "putin", "le pen", "melenchon", "obama", "zelensky", "xi jinping", "erdogan",
}

local ACCENTS = { ["é"]="e", ["è"]="e", ["ê"]="e", ["ë"]="e", ["à"]="a", ["â"]="a", ["î"]="i",
    ["ï"]="i", ["ô"]="o", ["ö"]="o", ["ù"]="u", ["û"]="u", ["ü"]="u", ["ç"]="c", ["É"]="e" }

local function words(text)
    local t = text:gsub("[\xC3\xC5][\x80-\xBF]", function(ch) return ACCENTS[ch] or " " end)
    return " " .. t:lower():gsub("[^%w]", " "):gsub("%s+", " ") .. " "
end

local BASE = { wyr = true, nhie = true, mlt = true, gtky = true, hotseat = true, dinner = true }

describe("content", function()
    for _, lang in ipairs({ "fr", "en" }) do
        it("has enough distinct cards in " .. lang .. " and nothing excluded", function()
            local cards, adult = loadCards(lang), 0
            local seen = {}
            for _, id in ipairs(Deck.ORDER) do
                local d = cards[id]
                assert.is_true(#d.family >= (BASE[id] and 300 or 200), id .. " " .. #d.family)
                adult = adult + #d.adult
                for _, l in ipairs({ d.family, d.adult }) do
                    for _, c in ipairs(l) do
                        assert.is_string(c)
                        assert.is_true(#c > 2 and #c <= 260, c)
                        assert.is_nil(seen[c], c)
                        seen[c] = true
                        local w = words(c)
                        for _, name in ipairs(EXCLUDED) do
                            assert.is_nil(w:find(" " .. name .. " ", 1, true), c)
                        end
                    end
                end
            end
            assert.is_true(adult >= 250, adult)
        end)
    end
end)

local small = {
    wyr     = { family = { "w1", "w2", "w3" }, adult = { "wa1" } },
    hotseat = { family = { "h1", "h2", "h3", "h4" }, adult = {} },
}

describe("deck", function()
    it("draws every family card exactly once, then finishes", function()
        local d = Deck.new{}
        assert.equals(7, d:build(small))
        local seen, n = {}, 0
        while d:next() do
            for _, id in ipairs(d:current()) do
                assert.is_nil(seen[id]); seen[id] = true; n = n + 1
                assert.is_not_nil(Deck.text(small, id))
                assert.is_nil(id:match(":a:"))
            end
        end
        assert.equals(7, n)
        assert.is_true(d:isFinished())
        assert.equals(7, d:cardsPlayed())
    end)

    it("adds adult cards only when asked", function()
        assert.equals(8, Deck.new{ adults = true }:build(small))
    end)

    it("filters by deck selection", function()
        local d = Deck.new{ decks = { wyr = true } }
        assert.equals(3, d:build(small))
    end)

    it("groups hot-seat questions by three", function()
        local d = Deck.new{ decks = { hotseat = true } }
        d:build(small)
        local first = d:next()
        assert.equals(3, #first)
        local second = d:next()
        assert.equals(1, #second)
        assert.is_nil(d:next())
    end)

    it("goes back and forward through the history", function()
        local d = Deck.new{ decks = { wyr = true } }
        d:build(small)
        local a = d:next()[1]
        local b = d:next()[1]
        assert.is_true(d:canGoBack())
        assert.equals(a, d:prev()[1])
        assert.is_false(d:canGoBack())
        assert.equals(b, d:next()[1])
        d:next(); assert.is_nil(d:next())
        assert.is_true(d:isFinished())
        d:prev()
        assert.is_false(d:isFinished())
        assert.equals(3, d.pos)
    end)

    it("gives turns round the table", function()
        local d = Deck.new{ decks = { wyr = true } }
        d:build(small)
        d:next(); assert.equals(1, d:turnIndex(2))
        d:next(); assert.equals(2, d:turnIndex(2))
        d:next(); assert.equals(1, d:turnIndex(2))
        assert.is_nil(d:turnIndex(0))
    end)

    it("round-trips through serialize/load", function()
        local d = Deck.new{ decks = { wyr = true, hotseat = true }, adults = true }
        d:build(small)
        d:next(); d:next()
        local d2 = Deck.load(d:serialize(), small)
        assert.same(d.pile, d2.pile)
        assert.same(d.history, d2.history)
        assert.equals(d.pos, d2.pos)
        assert.is_true(d2.adults)
        assert.is_true(d2:isSelected("wyr"))
        assert.is_false(d2:isSelected("mlt"))
        assert.equals(d.total, d2.total)
    end)

    it("rejects a save pointing at cards that no longer exist", function()
        local d = Deck.new{}
        d:build(small)
        d:next()
        local data = d:serialize()
        data.pile[1] = "wyr:f:99"
        assert.is_nil(Deck.load(data, small))
        assert.is_nil(Deck.load({ pile = "x" }))
    end)
end)
