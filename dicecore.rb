# ダイス関連の処理

# ダイス1つ
def dice(dice_size)
  ran = rand(1..dice_size)
end

# 複数ダイス[dice_num]D[dice_size]
def dices(dice_num, dice_size)
  dice_val = []
  for i in 1 .. dice_num do
    dice_val.push(dice(dice_size))
  end
  return dice_val.sum
end

# 複数ダイス、メッセージを返す版
def simple_dice(dice_num, dice_size)
  dice_val = []
  for i in 1 .. dice_num do
    dice_val.push(dice(dice_size))
  end
  msg = 'Insania: '+ dice_num.to_s + 'd' + dice_size.to_s + ' > ' +
        dice_val.to_s + ' > ' + dice_val.sum.to_s
  return msg
end

# 判定付き複数ダイス。大なりなどのconditionと判定用の値valueをとる
# 返り値はメッセージ
def judge_dice(dice_num, dice_size, condition, value)
  dice_val = []
  for i in 1 .. dice_num do
    dice_val.push(dice(dice_size))
  end
  result = "ERROR"
  case condition
  when "<=" || "=<" then
    dice_val.sum <= value ? result = "成功" : result = "失敗"
  when "<" then
    dice_val.sum < value ? result = "成功" : result = "失敗"
  when ">=" || "=>" then
    dice_val.sum >= value ? result = "成功" : result = "失敗"
  when ">" then
    dice_val.sum > value ? result = "成功" : result = "失敗"
  when "=" then
    dice_val.sum == value ? result = "成功" : result = "失敗"
  end
  msg = 'Insania: '+ dice_num.to_s + 'd' + dice_size.to_s + condition +
      value.to_s + ' > ' + dice_val.to_s + ' > ' +
      dice_val.sum.to_s + ' > ' + result
  return msg
end

# 複雑な式を判定の目標値に使う場合の判定付き複数ダイス
# 返り値はメッセージ
def judge_dice_with_formula(dice_num, dice_size, condition, value, formula)
  dice_val = []
  for i in 1 .. dice_num do
    dice_val.push(dice(dice_size))
  end
  result = "ERROR"
  case condition
  when "<=" || "=<" then
    dice_val.sum <= value ? result = "成功" : result = "失敗"
  when "<" then
    dice_val.sum < value ? result = "成功" : result = "失敗"
  when ">=" || "=>" then
    dice_val.sum >= value ? result = "成功" : result = "失敗"
  when ">" then
    dice_val.sum > value ? result = "成功" : result = "失敗"
  when "=" then
    dice_val.sum == value ? result = "成功" : result = "失敗"
  end
  formula_for_markdown = formula.gsub(/\*/, "\\*")
  msg = 'Insania: '+ dice_num.to_s + 'd' + dice_size.to_s + condition + 
        formula_for_markdown + ' > ' + dice_num.to_s + 'd' + dice_size.to_s +
        condition + value.to_s + ' > ' + dice_val.to_s + ' > ' + 
        dice_val.sum.to_s + ' > ' + result
  return msg
end

# 対抗ロール
def res(active, passive)
  result = "ERROR"
  value = 50 + (active*5 - passive*5)
  dice_value = dice(100)
  if dice_value <= value then
    result = "成功"
  else
    result = "失敗"
  end
  msg = 'Insania: 1d100<=' + value.to_s + ' > ' + 
        dice_value.to_s + ' > ' + result
  return msg
end

# 一時的狂気
def temp_madness()
  f = File.open("config/temp_madness.txt", mode="r:utf-8:utf-8")
  roll = f.read.split(/\R/)
  f.close
  msg = roll[dice(10)] + " ―  一時的狂気(" + 
        (dice(10)+4).to_s + "ラウンドまたは" + 
        (dice(6)*10+30).to_s + '分)'
  return msg
end

# 不定の狂気
def ind_madness()
  f = File.open("config/ind_madness.txt", mode="r:utf-8:utf-8")
  roll = f.read.split(/\R/)
  f.close
  msg = roll[dice(10)] + " ―  不定の狂気(" + (dice(10)*10).to_s + "時間)"
  return msg
end