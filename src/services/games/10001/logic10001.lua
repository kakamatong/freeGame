local logic = {}

function logic.init(playerNum, rule)
    logic.playerNum = playerNum
end

function logic.setPlayerNum(playerNum)
    logic.playerNum = playerNum
end

function logic.startGame()
    LOG.info("startGame")
end


return logic