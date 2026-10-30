local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local Blitbuffer      = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox      = require("ui/widget/confirmbox")
local Device          = require("device")
local Font            = require("ui/font")
local FrameContainer  = require("ui/widget/container/framecontainer")
local Geom            = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local LineWidget      = require("ui/widget/linewidget")
local RenderText      = require("ui/rendertext")
local Size            = require("ui/size")
local TextBoxWidget   = require("ui/widget/textboxwidget")
local TextWidget      = require("ui/widget/textwidget")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("i18n")
local T               = require("ffi/util").template

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")
local Deck        = lrequire("deck")
local PlayersMenu = lrequire("players")

local DeviceScreen = Device.screen

-- ---------------------------------------------------------------------------
-- Text sizing helpers (Font:getFace() scales by DPI: divide pixel sizes back)
-- ---------------------------------------------------------------------------

local DPI_SCALE = DeviceScreen:scaleBySize(1000) / 1000

local function pxFace(px)
    return Font:getFace("cfont", math.max(8, math.floor(px / DPI_SCALE)))
end

local function fitLine(text, px, max_w, bold)
    local face = pxFace(px)
    while px > 12 do
        local m = RenderText:sizeUtf8Text(0, max_w * 10, face, text, true, bold)
        if m.x <= max_w then break end
        px   = math.floor(px * 0.9)
        face = pxFace(px)
    end
    return TextWidget:new{ text = text, face = face, max_width = max_w, bold = bold }
end

local function wrapText(text, face, width, bold, align)
    return TextBoxWidget:new{ text = text, face = face, width = width, alignment = align or "center", bold = bold }
end

-- A wrapped paragraph at up to `px`, shrunk until it fits `max_h`.
local function fitBox(text, px, width, max_h, bold, align)
    local box
    while true do
        box = wrapText(text, pxFace(px), width, bold, align)
        if box:getSize().h <= max_h or px <= 14 then return box end
        box:free()
        px = math.floor(px * 0.92)
    end
end

-- Deck names in the menu follow KOReader's language; the heading on a card
-- follows the content language, like the card itself.
local DECK_LABELS = {
    wyr     = _("Would you rather"),
    nhie    = _("Never have I ever"),
    mlt     = _("Who's most likely to"),
    gtky    = _("Get to know you"),
    hotseat = _("Hot seat"),
    dinner  = _("Famous dinner"),
    dilemmas    = _("Dilemmas"),
    debates     = _("Absurd debates"),
    thisorthat  = _("This or that"),
    stories     = _("Story starters"),
    guesswho    = _("Guess who"),
    timemachine = _("Time machine"),
}

local DECK_TITLES = {
    fr = {
        wyr = "Tu préfères…", nhie = "Je n'ai jamais…", mlt = "Qui pourrait le plus…",
        gtky = "Pour mieux se connaître", hotseat = "Sur la sellette", dinner = "Dîner de légende",
        dilemmas = "Dilemme", debates = "Débat absurde", thisorthat = "Ceci ou cela ?",
        stories = "Il était une fois…", guesswho = "Qui est-ce ?", timemachine = "Machine à remonter le temps",
    },
    en = {
        wyr = "Would you rather…", nhie = "Never have I ever…", mlt = "Who's most likely to…",
        gtky = "Get to know you", hotseat = "Hot seat", dinner = "Famous dinner",
        dilemmas = "Dilemma", debates = "Absurd debate", thisorthat = "This or that?",
        stories = "Once upon a time…", guesswho = "Guess who?", timemachine = "Time machine",
    },
}

-- How to play the card, for the decks where reading it aloud isn't the
-- whole story (content language).
local DECK_HINTS = {
    fr = {
        guesswho = "Ne le lis pas à voix haute ! Décris ce personnage en trois mots : les autres devinent.",
        stories  = "Lis le début, puis chacun ajoute une phrase à son tour.",
    },
    en = {
        guesswho = "Don't read it out! Describe this person in three words: the others guess.",
        stories  = "Read the opening, then each player adds a sentence in turn.",
    },
}

local GAME_RULES_EN = [[
Party Questions — Rules

Whoever holds the reader reads the card aloud, then passes the reader on (or keeps it: you decide!).

• Would you rather… — everyone picks a side and defends it.
• Never have I ever… — those who HAVE done it own up (a point, a finger down, a sip of juice… house rules).
• Who's most likely to… — on three, everyone points at someone. Most pointed-at explains themselves.
• Get to know you — deep and fun questions, answer honestly.
• Hot seat — one player answers three questions in a row, no dodging.
• Famous dinner — imagine the evening and tell the table.

Choose the decks and the mode in the menu. "Adults" mode (opt-in) adds spicier questions — never explicit — for grown-up players only.

Add player names to see whose turn it is. Cards come in a random order without repeats; "Previous" goes back. When the deck is exhausted, start a new game.
]]

local GAME_RULES_FR = [[
Questions de soirée — Règles

Celui qui tient la liseuse lit la carte à voix haute, puis la passe à son voisin (ou la garde : c'est vous qui voyez !).

• Tu préfères… — chacun choisit son camp et le défend.
• Je n'ai jamais… — ceux qui L'ONT fait se dénoncent (un point, un doigt baissé, une gorgée de jus de pomme… à vous de fixer la règle).
• Qui pourrait le plus… — à trois, tout le monde pointe quelqu'un du doigt. Le plus désigné se justifie.
• Pour mieux se connaître — questions profondes ou rigolotes, on répond franchement.
• Sur la sellette — un joueur répond à trois questions d'affilée, sans se défiler.
• Dîner de légende — imaginez la soirée et racontez-la à la table.

Choisissez les paquets et le mode dans le menu. Le mode « Adultes » (à activer soi-même) ajoute des questions plus piquantes — jamais explicites — réservées aux grands.

Ajoutez les prénoms des joueurs pour savoir à qui c'est le tour. Les cartes arrivent dans le désordre, sans répétition ; « Précédent » revient en arrière. Quand le paquet est épuisé, lancez une nouvelle partie.
]]

-- French typography: a no-break space before « ? ! : ; » and inside
-- guillemets, so a lone "?" never wraps onto its own line.
local NBSP = "\u{00A0}"
local function frenchSpaces(s)
    return (s:gsub(" ([%?!:;»])", NBSP .. "%1"):gsub("« ", "«" .. NBSP))
end

-- ---------------------------------------------------------------------------
-- PartyQuestionsScreen
-- ---------------------------------------------------------------------------

local PartyQuestionsScreen = ScreenBase:extend{}

function PartyQuestionsScreen:init()
    local p = self.plugin
    self.lang    = p:getSetting("lang", _.lang() == "fr" and "fr" or "en")
    self.adults  = p:getSetting("adults", false) and true or false
    self.decks   = self:_loadDeckSelection()
    local names  = p:getSetting("names")
    self.names   = type(names) == "table" and names or {}
    self.cards   = {}

    local saved = p:loadState()
    if type(saved) == "table" and saved.lang == self.lang then
        self.deck = Deck.load(saved.deck, self:_cards())
    end
    if not self.deck then self:_newDeck() end
    ScreenBase.init(self)
end

function PartyQuestionsScreen:_loadDeckSelection()
    local saved = self.plugin:getSetting("decks", "")
    if type(saved) ~= "string" or saved == "" then return nil end
    local sel = {}
    for id in saved:gmatch("[^,]+") do sel[id] = true end
    return sel
end

function PartyQuestionsScreen:_saveDeckSelection()
    local parts = {}
    for id in pairs(self.decks or {}) do parts[#parts + 1] = id end
    table.sort(parts)
    self.plugin:saveSetting("decks", table.concat(parts, ","))
end

-- Card text for the content language, loaded lazily deck by deck.
function PartyQuestionsScreen:_cards()
    local lang = self.lang
    if not self.cards[lang] then
        local all = {}
        for _i, id in ipairs(Deck.ORDER) do
            local chunk = loadfile(_dir .. "cards/" .. lang .. "/" .. id .. ".lua")
            local ok, t = pcall(chunk or error)
            if ok and type(t) == "table" then all[id] = t end
        end
        self.cards[lang] = all
    end
    return self.cards[lang]
end

function PartyQuestionsScreen:_text(id)
    local s = Deck.text(self:_cards(), id) or "?"
    if self.lang == "fr" then s = frenchSpaces(s) end
    return s
end

function PartyQuestionsScreen:_newDeck()
    self.deck = Deck.new{ decks = self.decks, adults = self.adults }
    self.deck:build(self:_cards())
    self.deck:next()
end

function PartyQuestionsScreen:serializeState()
    return { lang = self.lang, deck = self.deck:serialize() }
end

function PartyQuestionsScreen:_save()
    self.plugin:saveState(self:serializeState())
end

function PartyQuestionsScreen:_refresh()
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

function PartyQuestionsScreen:onNewGame()
    self:_newDeck()
    self:_save()
    self:_refresh()
end

function PartyQuestionsScreen:onNext()
    self.deck:next()
    self:_save()
    self:_refresh()
    self:refreshActionBar()
end

function PartyQuestionsScreen:onPrev()
    self.deck:prev()
    self:_save()
    self:_refresh()
    self:refreshActionBar()
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

function PartyQuestionsScreen:openLangMenu()
    MenuHelper.openPickerMenu{
        title      = _("Language"),
        items      = { { id = "fr", text = "Français" }, { id = "en", text = "English" } },
        current_id = self.lang,
        parent     = self,
        on_select  = function(lang)
            if lang == self.lang then return end
            self.lang = lang
            self.plugin:saveSetting("lang", lang)
            self:onNewGame()
        end,
    }
end

function PartyQuestionsScreen:openPlayersMenu()
    PlayersMenu.open{
        names     = self.names,
        min       = 0,
        max       = 20,
        parent    = self,
        on_change = function(list)
            self.names = list
            self.plugin:saveSetting("names", list)
            self:_refresh()
        end,
    }
end

function PartyQuestionsScreen:_decksText()
    if self.decks == nil then return T(_("Decks: %1"), _("all")) end
    local n = 0
    for _id in pairs(self.decks) do n = n + 1 end
    return T(_("Decks: %1"), n .. "/" .. #Deck.ORDER)
end

-- Multi-select: each tap toggles one deck and re-opens the menu. The last
-- selected deck can't be switched off. Applied as a new game on change.
function PartyQuestionsScreen:openDecksMenu()
    local cards = self:_cards()
    local items = {}
    for _i, id in ipairs(Deck.ORDER) do
        local d = cards[id] or {}
        local count = #(d.family or {}) + (self.adults and #(d.adult or {}) or 0)
        local on = self.decks == nil or self.decks[id]
        items[#items + 1] = {
            id   = id,
            text = (on and "✓ " or "○ ") .. DECK_LABELS[id] .. string.format("  (%d)", count),
        }
    end
    items[#items + 1] = { id = "__all__", text = "★ " .. _("All decks") }
    MenuHelper.openPickerMenu{
        title     = _("Decks"),
        items     = items,
        parent    = self,
        on_select = function(id)
            if id == "__all__" then
                self.decks = nil
            else
                local sel = {}
                for _i, d in ipairs(Deck.ORDER) do
                    if self.decks == nil or self.decks[d] then sel[d] = true end
                end
                if sel[id] then sel[id] = nil else sel[id] = true end
                local n, all = 0, true
                for _i, d in ipairs(Deck.ORDER) do
                    if sel[d] then n = n + 1 else all = false end
                end
                if n == 0 then
                    self:showMessage(_("Keep at least one deck."))
                    self:openDecksMenu()
                    return
                end
                self.decks = (not all) and sel or nil
            end
            self:_saveDeckSelection()
            self:onNewGame()
            self:openDecksMenu()
        end,
    }
end

function PartyQuestionsScreen:_setAdults(on)
    self.adults = on
    self.plugin:saveSetting("adults", on)
    self:onNewGame()
end

function PartyQuestionsScreen:openModeMenu()
    MenuHelper.openPickerMenu{
        title      = _("Mode"),
        items      = {
            { id = false, text = _("Family") },
            { id = true,  text = _("Adults") .. " — " .. _("spicier, never explicit") },
        },
        current_id = self.adults,
        parent     = self,
        on_select  = function(on)
            if on == self.adults then return end
            if not on then self:_setAdults(false); return end
            UIManager:show(ConfirmBox:new{
                text = _("Adults mode adds spicier questions about dating, exes and embarrassing nights — never explicit. For grown-up players only.\n\nSwitch it on?"),
                ok_text = _("Adults"),
                ok_callback = function() self:_setAdults(true) end,
            })
        end,
    }
end

function PartyQuestionsScreen:_titleBar()
    return self:buildTitleBar(_("Party Questions"), function()
        return {
            { text = _("New game"), callback = function() self:onNewGame() end },
            { text = T(_("Language: %1"), self.lang:upper()), callback = function() self:openLangMenu() end },
            { text = #self.names > 0 and T(_("Players: %1"), #self.names) or _("Players: none"),
              callback = function() self:openPlayersMenu() end },
            { text = self:_decksText(), callback = function() self:openDecksMenu() end },
            { text = T(_("Mode: %1"), self.adults and _("Adults") or _("Family")),
              callback = function() self:openModeMenu() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
        }
    end)
end

-- ---------------------------------------------------------------------------
-- Round over: the deck is exhausted
-- ---------------------------------------------------------------------------

function PartyQuestionsScreen:isRoundOver()
    return self.deck:isFinished()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

local function vspan(h) return VerticalSpan:new{ width = h } end

function PartyQuestionsScreen:_buildControls()
    local rows = {
        { text = "◀  " .. _("Previous"), enabled = self.deck:canGoBack(), callback = function() self:onPrev() end },
        { text = _("Next") .. "  ▶", callback = function() self:onNext() end },
    }
    self.status_text:setMaxWidth(self:getControlsWidth())
    return VerticalGroup:new{
        align = "center",
        self.status_text,
        VerticalSpan:new{ width = Size.span.vertical_large },
        self:buildActionBar(rows),
    }
end

function PartyQuestionsScreen:buildLayout()
    local title_bar = self:_titleBar()
    local controls  = self:_buildControls()
    local bw, bh    = self:getBoardBudget(title_bar, controls)
    local content
    if self.deck:isFinished() then
        content = self:_finishedView(bw, bh)
    else
        content = self:_cardView(bw, bh)
    end
    if self:isLandscape() then
        self:buildLandscapeLayout(title_bar, HorizontalGroup:new{
            align = "center",
            content,
            HorizontalSpan:new{ width = self:getGutter() },
            controls,
        })
    else
        self:buildPortraitLayout(title_bar, content,
            VerticalGroup:new{ align = "center", controls, VerticalSpan:new{ width = self:getGutter() } })
    end
    self[1] = self.layout
    self:updateStatus()
end

function PartyQuestionsScreen:_turnLine(deck_id)
    local i = self.deck:turnIndex(#self.names)
    if not i then return nil end
    local name = self.names[i]
    if deck_id == Deck.HOT_SEAT then return T(_("%1 in the hot seat!"), name) end
    return T(_("%1, your turn!"), name)
end

function PartyQuestionsScreen:_cardView(bw, bh)
    local entry = self.deck:current()
    local short = math.min(bw, bh)
    local vs    = Size.span.vertical_large
    if not entry then
        return wrapText(_("No cards in the selected decks."), Font:getFace("infofont"), bw)
    end
    local deck_id = Deck.parseId(entry[1])
    local titles  = DECK_TITLES[self.lang] or DECK_TITLES.en

    local head = { align = "center" }
    local turn = self:_turnLine(deck_id)
    if turn then
        head[#head + 1] = fitLine(turn, short * 0.075, bw, true)
        head[#head + 1] = vspan(vs * 2)
    end
    head = VerticalGroup:new(head)

    local pad     = Size.padding.large * 2
    local border  = Size.border.window
    local inner_w = bw - 2 * (pad + border)
    local title   = fitLine(titles[deck_id] or "", short * 0.06, inner_w, true)
    local line    = LineWidget:new{
        background = Blitbuffer.COLOR_DARK_GRAY,
        dimen      = Geom:new{ w = math.floor(inner_w * 0.4), h = Size.line.medium },
    }
    local hint_text = (DECK_HINTS[self.lang] or DECK_HINTS.en)[deck_id]
    local hint = hint_text and wrapText(self.lang == "fr" and frenchSpaces(hint_text) or hint_text,
        pxFace(short * 0.04), inner_w)
    local fixed = head:getSize().h + title:getSize().h + line:getSize().h + vs * 4 + 2 * (pad + border)
        + (hint and hint:getSize().h + vs * 2 or 0)
    local max_text_h = math.max(60, bh - fixed)

    local text
    if #entry > 1 then
        local lines = {}
        for k, id in ipairs(entry) do lines[k] = k .. ". " .. self:_text(id) end
        text = fitBox(table.concat(lines, "\n\n"), short * 0.065, inner_w, max_text_h, false, "left")
    else
        local big = deck_id == "guesswho"
        text = fitBox(self:_text(entry[1]), short * (big and 0.11 or 0.085), inner_w, max_text_h, big)
    end
    local group = VerticalGroup:new{ align = "center", title, vspan(vs), line, vspan(vs * 3) }
    if hint then
        group[#group + 1] = hint
        group[#group + 1] = vspan(vs * 2)
    end
    group[#group + 1] = text

    -- The card fills the room left so it doesn't jump in size card to card.
    local card_h = math.max(group:getSize().h, bh - head:getSize().h - 2 * (pad + border))
    local frame = FrameContainer:new{
        padding    = pad,
        margin     = 0,
        bordersize = border,
        radius     = Size.radius.window,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = card_h },
            group,
        },
    }
    return VerticalGroup:new{ align = "center", head, frame }
end

function PartyQuestionsScreen:_finishedView(bw, bh)
    local short = math.min(bw, bh)
    local vs = Size.span.vertical_large
    return VerticalGroup:new{
        align = "center",
        fitLine(_("That's the whole deck!"), short * 0.09, bw, true),
        vspan(vs * 3),
        wrapText(T(_("%1 questions played. Start a new game to shuffle them again, or pick other decks in the menu."),
            self.deck:cardsPlayed()), pxFace(short * 0.05), bw),
    }
end

-- ---------------------------------------------------------------------------
-- Status bar: "Card 12/480 · Family"
-- ---------------------------------------------------------------------------

function PartyQuestionsScreen:updateStatus(msg)
    if msg then ScreenBase.updateStatus(self, msg); return end
    local d = self.deck
    local played = d:cardsPlayed()
    if not d:isFinished() then
        -- cardsPlayed counts every question drawn; going back shows an
        -- earlier one, so count the history up to the current position.
        played = 0
        for k = 1, d.pos do played = played + #d.history[k] end
    end
    ScreenBase.updateStatus(self, self:joinStatus(
        T(_("Card %1/%2"), played, d.total),
        self.adults and _("Adults") or _("Family"),
        self.lang:upper()))
end

return PartyQuestionsScreen
