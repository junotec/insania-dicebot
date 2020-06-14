::RBNACL_LIBSODIUM_GEM_LIB_PATH = 'C:\Windows\System32\libsodium.dll' #windows用
require 'discordrb'
require './gspsheet'
require './dicecore'

# メインファイル。主にDiscordとのやり取り関連を記述

# 設定ファイルをJsonとして読み込み、代入
config = File.open("config/config.json")
hash = JSON.load(config)
TOKEN = hash["bot_token"]
CLIENT_ID = hash["bot_client_id"]

# Botの設定
bot = Discordrb::Commands::CommandBot.new token: TOKEN,
client_id: CLIENT_ID, prefix: "x"

# ニックネームが無い場合のエラー回避
def get_user_name(user)
  if user.nick != nil   
    return user.nick
  elsif user.name != nil    
    return user.name
  else
    return "Unknown User"
  end
end

# rescueでDiscordに例外を出力している関係で通常ではログに例外が出ないので、
# 出力のための関数(ひどい対応なので今後どうにかする)
def print_error(error)
  puts error.class.to_s + ": " + error.message
  puts error.backtrace
end

bot.message do |event|
  # discordrbのコマンドの形に収まらないダイスコマンド全般を扱うブロック。
  # 基本は正規表現で必要部分を検出して処理する
  content_raw = event.message.content
  
  # 正規表現で扱いやすいように主要な全角文字を半角に、大文字Dを小文字に、
  # 不等号イコールの表記を揃える
  content = content_raw.tr('０-９ａ-ｚＡ-Ｚ＜＝＞＋－＊',
                           '0-9a-zA-Z<=>+\-*').gsub(/D|=<|=>|　/,
                                                    "D" => "d",
                                                    "=<" => "<=",
                                                    "=>" => ">=",
                                                    "　" => "\s")
  
  # MdN<=Oのような場合の区切りの都合上末尾に半角スペースを挿入する。
  content_nbsp = content + "\s"
  
  # 以下場合毎にダイス数などを正規表現で抜き出し、適切なダイスの関数に渡す
  
  # 判定なしダイス
  if /^\d+d\d+\s.*$/ =~ content   
    md = content_nbsp.match(/.+(?=d)/)
    nd = content_nbsp.match(/(?<=d).*?(?=\s)/)
    dice_num = md[0]
    dice_size = nd[0]
    event.respond '\> ' + get_user_name(event.user) + "\n" +
                  simple_dice(dice_num.to_i, dice_size.to_i)
  
  # <=ダイス
  elsif /^\d+d\d+<=\d+$/ =~ content || /^\d+d\d+<=\d+\s.*$/ =~ content   
    ld = content_nbsp.match(/.+(?=d)/)
    md = content_nbsp.match(/(?<=d).*?(?=<)/)
    nd = content_nbsp.match(/(?<==).*?(?=\s)/)
    dice_num = ld[0]
    dice_size = md[0]
    value = nd[0]
    event.respond '\> ' + get_user_name(event.user) + "\n" +
                  judge_dice(dice_num.to_i, dice_size.to_i, "<=", value.to_i)
  
  # <ダイス
  elsif /^\d+d\d+<\d+$/ =~ content || /^\d+d\d+<\d+\s.*$/ =~ content   
    ld = content_nbsp.match(/.+(?=d)/)
    md = content_nbsp.match(/(?<=d).*?(?=<)/)
    nd = content_nbsp.match(/(?<=<).*?(?=\s)/)
    dice_num = ld[0]
    dice_size = md[0]
    value = nd[0]
    event.respond '\> ' + get_user_name(event.user) + "\n" +
                  judge_dice(dice_num.to_i, dice_size.to_i, "<", value.to_i)
  
  # >=ダイス
  elsif /^\d+d\d+>=\d+$/ =~ content || /^\d+d\d+>=\d+\s.*$/ =~ content   
    ld = content_nbsp.match(/.+(?=d)/)
    md = content_nbsp.match(/(?<=d).*?(?=>)/)
    nd = content_nbsp.match(/(?<==).*?(?=\s)/)
    dice_num = ld[0]
    dice_size = md[0]
    value = nd[0]
    event.respond '\> ' + get_user_name(event.user) + "\n" +
                  judge_dice(dice_num.to_i, dice_size.to_i, ">=", value.to_i)
  
  # >ダイス
  elsif /^\d+d\d+>\d+$/ =~ content || /^\d+d\d+>\d+\s.*$/ =~ content   
    ld = content_nbsp.match(/.+(?=d)/)
    md = content_nbsp.match(/(?<=d).*?(?=>)/)
    nd = content_nbsp.match(/(?<=>).*?(?=\s)/)
    dice_num = ld[0]
    dice_size = md[0]
    value = nd[0]
    event.respond '\> ' + get_user_name(event.user) + "\n" +
                  judge_dice(dice_num.to_i, dice_size.to_i, ">", value.to_i)
  
  # = ダイス
  elsif /^\d+d\d+=\d+$/ =~ content || /^\d+d\d+=\d+\s.*$/ =~ content   
    ld = content_nbsp.match(/.+(?=d)/)
    md = content_nbsp.match(/(?<=d).*?(?==)/)
    nd = content_nbsp.match(/(?<==).*?(?=\s)/)
    dice_num = ld[0]
    dice_size = md[0]
    value = nd[0]
    event.respond '\> ' + get_user_name(event.user) + "\n" +
                  judge_dice(dice_num.to_i, dice_size.to_i, "=", value.to_i)
    
  # 複数ダイス。ダイスを各自振った後元の式に代入し、evalでそのまま計算。
  elsif /^\d+d\d+[d\d\+\-*\/\(\)]*/ =~ content   
    # MdNの形の部分を全て検出
    content_dices = content_nbsp.scan(/\d+d\d+/)
    # ダイスの個数と値の上限、振った結果を格納する配列をそれぞれ用意
    dice_nums = []
    dice_sizes = []
    results = []
    # コメント部分と式の部分を半角スペースで切り離す
    content_converted = content_nbsp.match(/.*?(?=\s)/)[0]
    for i in 0..content_dices.length - 1 do
      dice_nums.push(content_dices[i].match(/.+(?=d)/)[0])
      dice_sizes.push(content_dices[i].match(/(?<=d).*/)[0])
      results.push(dices(dice_nums[i].to_i, dice_sizes[i].to_i))
      # 出目を式に代入、数字と演算記号のみの式とする
      content_converted = content_converted.sub(dice_nums[i] + "d" + 
                                                dice_sizes[i], results[i].to_s)
    end 
    k = eval(content_converted)
    event.respond '\> ' + get_user_name(event.user) + "\n" + 'Insania: ' +
                  content_nbsp.match(/.*?(?=\s)/)[0].gsub('*', '\*') + ' > ' +
                  content_converted.gsub('*', '\*') + ' > ' + k.to_s
  end
  
  # 従来の対抗ロール。
  if /^res\(\d+-\d+\)\s.*$/ =~ content   
    md = content.match(/(?<=\().*?(?=-)/)
    nd = content.match(/(?<=-).*?(?=\))/)
    active = md[0]
    passive = nd[0]
    event.respond '\> ' + get_user_name(event.user) + "\n" +
                  res(active.to_i, passive.to_i)
  end
end

# コマンド版の対抗ロール
bot.command :res do |event,active,passive|
  event.respond '\> ' + get_user_name(event.user) + "\n" + 
                res(active.to_i, passive.to_i)
end

# 狂気表。typeは一時的狂気/不定の狂気の指定用
bot.command :mad do |event,type|
  if type == "temp"   
    event.respond '\> ' + get_user_name(event.user) + "\n" + temp_madness()
  elsif type == "ind"   
    event.respond '\> ' + get_user_name(event.user) + "\n" + ind_madness()
  end
end

# 選択。任意個数の選択肢から1つ選択
bot.command :choice do |event, *options|
  event.respond '\> ' + get_user_name(event.user) + "\nInsania: choice" +
                options.to_s + " > " + options[rand(options.length)]
end

# --以下Google Spreadsheetがらみの処理--
# 処理の具体的中身はgspsheet.rbで

# 新規シートの作成
bot.command :newsheet do |event, name|
  begin
    newsheet(name)
    i = newsheet_id_add(name)
    event.respond "新規シート「" + name + "」が作成されました。
                   idは**"+ i.to_s + "**。" 
  rescue =>e
    event.respond "[" + e.class.to_s + "] " +  e.message.to_s
    print_error(e)
  end
end

# シートとidの対応表表示
bot.command :sheetlist do |event|
  event.respond show_list
end

# 能力値ダイスを振る
bot.command :statusgen do |event, name|
  begin
    if sheet_locked?(name) == true   
      event.respond "シート「"+ name +"」はロックされています。"
    else
      status_gen(name)
      event.respond "シート「" + name + "」の能力値ダイスを振りました。"
    end
    rescue NoMethodError => e1
      event.respond "そのような名前のシートは存在しません。(" + "[" + 
                     e1.class.to_s + "] " + e1.message.to_s + ")"
      print_error(e1)
    rescue =>e2
      event.respond "[" + e2.class.to_s + "] " + e2.message.to_s
      print_error(e2)
  end
end

# シートのロック(能力値振り直しを禁止)
bot.command :lock do |event, name|
  begin
    sheet_lock(name)
    event.respond "シートをロックしました。"
  rescue NoMethodError => e1
    event.respond "そのような名前のシートは存在しません。(" + "[" + 
                   e1.class.to_s + "] " + e1.message.to_s + ")"
    print_error(e1)
  rescue =>e2
    event.respond "[" + e2.class.to_s + "] " + e2.message.to_s
    print_error(e2)
  end
end

# シートのアンロック
bot.command :unlock do |event, name|
  begin
    sheet_unlock(name)
    event.respond "シートのロックを解除しました。"
  rescue NoMethodError => e1
    event.respond "そのような名前のシートは存在しません。(" + "[" + 
                   e1.class.to_s + "] " + e1.message.to_s + ")"
    print_error(e1)
  rescue =>e2
    event.respond "[" + e2.class.to_s + "] " + e2.message.to_s
    print_error(e2)
  end
end

# シートの値1つの変更
bot.command :change do |event, name, skill, value, type|
  begin
    if sheet_locked?(name) == true   
      event.respond "シート「"+ name +"」はロックされています。"
    elsif type_abbr_to_type(type) == "合計値"   
      event.respond "合計値は手動変更できません。"
    else
      change_value(name, skill, value, type)
      event.respond "「" + name + "」の" + skill + "に" + 
                    type_abbr_to_type(type) + value + "を追加しました。"
    end
  rescue =>e
    event.respond "[" + e.class.to_s + "] " +  e.message.to_s
    print_error(e)
  end
end


# シートのある値の中身を表示
bot.command :show do |event, name, skill, type="合計値"|
  begin
    event.respond skill + "(" + type_abbr_to_type(type) + "): " +
                  show_value(name, skill, type)
  rescue NoMethodError => e1
    event.respond "そのような名前のシートは存在しません。(" + "[" +
                  e1.class.to_s + "] " + e1.message.to_s + ")"
    print_error(e1)
  rescue =>e2
    event.respond "[" + e2.class.to_s + "] " + e2.message.to_s
    print_error(e2)
  end
end

# シート全体をテキストとして表示
bot.command :showsheet do |event, name|
  begin
    # 字数制限2000字を超える場合は分割する
    msg = show_sheet(name)
    if msg.length > 2000   
      msgs = msg.scan(/.{1,#{2000}}/m)
      msgs.each { |msg_part| event.respond msg_part }
    else
      event.respond msg
    end
  rescue NoMethodError => e1
    event.respond "そのような名前のシートは存在しません。(" + "[" +
                  e1.class.to_s + "] " + e1.message.to_s + ")"
    print_error(e1)
  rescue =>e2
    event.respond "[" + e2.class.to_s + "] " + e2.message.to_s
    print_error(e2)
  end
end

# シートの削除。確認機能付き
bot.command :delsheet do |event, name|
  begin
    if name == "対応表" || name == "Sheet1"   
      event.respond "そのシートは削除できません。"
    else
      event.user.await(:confirm) do |confirm_event|
        if confirm_event.message.content == name   
          delete_sheet(name)
          event.respond "シート「" + name + "」を削除しました。"
        else
          event.respond "シート名が間違っています。処理を終了します。"
        end
      end
      event.respond "本当にシート「" + name + "」を削除しますか? この操作は
                     取り消せません。\n続行する場合にはシート名を正確に入力
                     してください。"
    end
  rescue NoMethodError => e1
    event.respond "そのような名前のシートは存在しません。(" + "[" +
                   e1.class.to_s + "] " + e1.message.to_s + ")"
    print_error(e1)
  rescue =>e2
    event.respond "[" + e2.class.to_s + "] " + e2.message.to_s
    print_error(e2)
  end
end
    
bot.command :reloadskills do |event|
  begin
    reload_skills("Sheet1")
    event.respond "技能表を更新しました。"
  rescue =>e
    event.respond "[" + e.class.to_s + "] " + e.message.to_s
    print_error(e)
  end
end
    
# シートを利用した自動判定。簡単な計算機能付き。
# オプションで判定の種類とダイスを変更可
bot.command :i do |event, id, skill,
                   dice_num = "1", dice_size = "100", type = "<="|
  begin
    if skill =~ /\A[^*\+\-\/]+[*\/\+\-]\d+[\d\+\-*\/\(\)]*\z/   
      skill_name = skill.gsub(/\A([^*\+\-\/]+)[*\/\+\-]\d+[\d\+\-*\/\(\)]*\z/,
                              '\1')
      skill_val = skill_value(id_to_title(id.to_i), skill_name)
      formula = skill.sub(/\A[^*\+\-\/]+([*\/\+\-]\d+[\d\+\-*\/()]*)\z/,
                          skill_val.to_s + '\1')
      value = eval(formula)
      event.respond '\> ' + get_user_name(event.user) + "\n" +
                    judge_dice_with_formula(dice_num.to_i, dice_size.to_i,
                                            type, value, formula)
    else
      skill_val = skill_value(id_to_title(id.to_i), skill)
      event.respond '\> ' + get_user_name(event.user) + "\n" +
                    judge_dice(dice_num.to_i, dice_size.to_i, type, skill_val)
    end
  rescue NoMethodError => e1
    event.respond "そのようなIDのシートは存在しません。(" + "[" +
                  e1.class.to_s + "] " + e1.message.to_s + ")"
    print_error(e1)
  rescue ArgumentError => e2
    event.respond "技能名かIDが間違っています。(" + "[" + e2.class.to_s + "] " +
                  e2.message.to_s + ")"
    print_error(e2)
  rescue =>e3
    event.respond "[" + e3.class.to_s + "] " + e3.message.to_s
    print_error(e3)
  end
end

# 正気度の減少(よく使う＋SANと混同しやすいので:changeとは別にコマンド化)
bot.command :san do |event, id, value|
  begin
    add_value(id_to_title(id.to_i), "正気度", value, "minus")
    previous_san = show_value(id_to_title(id.to_i), "正気度", "sum").to_i +
                   value.to_i
    current_san = show_value(id_to_title(id.to_i), "正気度", "sum")
    event.respond "SAN" + previous_san.to_s + "→" + current_san
  rescue =>e
    event.respond "[" + e.class.to_s + "] " +  e.message.to_s
    print_error(e)
  end
end

# 正気度の回復
bot.command :sanr do |event, id, value|
  begin
    # 減少値なので符号を反転
    value = (-value.to_i).to_s
    add_value(id_to_title(id.to_i), "正気度", value, "minus")
    previous_san = show_value(id_to_title(id.to_i), "正気度", "sum").to_i +
                   value.to_i
    current_san = show_value(id_to_title(id.to_i), "正気度", "sum")
    event.respond "SAN" + previous_san.to_s + "→" + current_san
  rescue =>e
    event.respond "[" + e.class.to_s + "] " +  e.message.to_s
    print_error(e)
  end
end
    
# ヘルプの表示。
bot.command :help do |event|
  f = File.open("config/helptext.txt", mode = "rt:utf-8:utf-8")
  help = f.read
  f.close
  event.respond help
end

bot.run