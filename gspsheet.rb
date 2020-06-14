require "google_drive"
require "json"
require "./dicecore"


# config.jsonを読み込んでセッションを確立
session = GoogleDrive::Session.from_config("config/spreadsheet_config.json")
# URLからスプレッドシートを開く
config = JSON.load(File.open("config/config.json"))
$sp = session.spreadsheet_by_url(config["drive_url"])

# 新規のデフォルト値シート(空)の作成を行う関数
def newsheet(newtitle)
  # コピー元のデフォルトシートを開く
  defaultws = $sp.worksheet_by_title("Sheet1")
  # 複製。名前は日本語版ならSheet1 のコピー となる
  defaultws.duplicate
  # 複製後のIDを取得
  dupsheet = $sp.worksheet_by_title("Sheet1 のコピー")
  dupsheet.title = newtitle
  dupsheet.save
end

# 指定した名前を対応表に追加。newsheet時の処理だが一応分離
def newsheet_id_add(pc_name)
  list = $sp.worksheet_by_title("対応表")
  i = 1
  while list[i,1] != ""
    i = i + 1
  end
  list[i,1] = pc_name
  list.save
  return i
end

# idを受取り対応するタイトルを返す
def id_to_title(id)
  list = $sp.worksheet_by_title("対応表")
  return list[id,1]
end

# タイトルを受け取りidを返す
def title_to_id(title)
  list = $sp.worksheet_by_title("対応表")
  i = 1
  while list[i,1] != title
    i += 1
  end
  return i
end

# シートの削除。対応表からも消す
def delete_sheet(pc_title)
  ws = $sp.worksheet_by_title(pc_title)
  ws.delete
  list = $sp.worksheet_by_title("対応表")
  list.delete_rows(title_to_id(pc_title), 1)
  list.save
end

# 指定したPCのシートの能力値をランダム生成
def status_gen(pc_title)
  ws = $sp.worksheet_by_title(pc_title)
  # worksheet.listは1行目の内容を列のタイトルとして、列番号の代わりに
  # そのタイトルとセル内容を関連付けたハッシュ(1行1つ)の配列。
  # この場合の行指定は、2行目が「0」となる。(通常は左上のセルが[1,1]となる)
  for i in 0..4 # STR,CON,POW,DEX,APP
    ws.list[i]["初期値"] = dices(3,6).to_s
  end
  for i in 5..6 # SIZ,INT
    ws.list[i]["初期値"] = (dices(2,6)+6).to_s
  end
  # EDU
  ws.list[7]["初期値"] = (dices(3,6)+3).to_s
  ws.save
end

# シートのロック
def sheet_lock(pc_title)
  list = $sp.worksheet_by_title("対応表")
  id = title_to_id(pc_title)
  list[id,2] = "YES"
  list.save
end

# シートのロック解除
def sheet_unlock(pc_title)
  list = $sp.worksheet_by_title("対応表")
  id = title_to_id(pc_title)
  list[id,2] = "NO"
  list.save
end

# シートがロックされているかを返す
def sheet_locked?(pc_title)
  list = $sp.worksheet_by_title("対応表")
  id = title_to_id(pc_title)
  return list[id,2] == "YES" ? true : false
end

# 行と列の数字からセル名文字列(A1など)を導く
def row_col_to_cell_name(row, col)
  # chrで数字から英字に変換する
  # 65.chr #=> "A"
  col_character = (col + 64).chr
  return col_character + row.to_s
end

# 1行目の内容を列タイトルとして、そのタイトルから列番号を引く。
# 列数が膨大になるのは考えづらいので工夫なく線形探索で済ませている
def column_title_to_column(ws, column_title)
  i = 1
  while ws[1,i] != ""
  return i if ws[1,i] == column_title
  i += 1
  end
  raise(ArgumentError, format('Found no column with the title provided: %p', 
        column_title))
end

# 技能/能力値名から行数を出すためのハッシュの更新
def reload_skills(pc_title)
  i = 1
  ws = $sp.worksheet_by_title(pc_title)
  skills = {}
  while ws[i,1] != ""
    skills[ws[i,1]] = i
    # 合計値の式が未設定の場合、入力する(やや柔軟性に欠ける)
    if ws.list[i-2]["合計値"] == "" then
      ini_val_cell = row_col_to_cell_name(i, 
                                          column_title_to_column(ws, "初期値"))
      hob_val_cell = row_col_to_cell_name(i, 
                                          column_title_to_column(ws, "趣味P"))
      minus_val_cell = row_col_to_cell_name(i, 
                                            column_title_to_column(ws, "減少値"))
      ws.list[i-2]["合計値"] = "=SUM(" + ini_val_cell + ":" + 
                               hob_val_cell + ")-" + minus_val_cell
      ws.save if ws.dirty?
    end
    i += 1
  end
  # Unicodeデコード
  skills.each do |k, v|
    k = k.gsub(/\\u([\da-fA-F]{4})/) { [$1].pack('H*').unpack('n*').pack('U*') }
  end
  File.open("config/skills.json", mode = "w") do |f|
    JSON.dump(skills, f)
  end
end

# 略称を技能種別に変換。略称が無い(そのまま)の場合はそのまま返す
# ここも設定可能にしてもいいが、需要があるか微妙
def type_abbr_to_type(abbr)
  hash = {
  'occup' => '職業P',
  'hobby' => '趣味P',
  'minus' => '減少値',
  'sum'   => '合計値'
  }
  # 部分一致回避のために長さに順に並べ…
  keys = hash.keys.sort_by{|s| -s.length}
  # …置き換え用の正規表現オブジェクトを得る。
  re = Regexp.union(keys)
  abbr = abbr.gsub(re, hash)
  return abbr
end

# 指定した技能の指定した種別の値の変更
def change_value(pc_title, skill, value, type)
  ws = $sp.worksheet_by_title(pc_title)
  # 技能名とIDの対応表(ファイルから読み取り、ハッシュにする)
  f = File.open("config/skills.json")
  skills_json = f.read  # 全て読み込む
  f.close
  # scanでハッシュに変換
  skills = JSON.parse(skills_json)
  ws.list[skills[skill]-2][type_abbr_to_type(type)] = value
  ws.save
end

# 指定した技能の指定した種別の値への「加算」
# この場合のvalueは足す値であり、目標値ではない
def add_value(pc_title, skill, value, type)
  ws = $sp.worksheet_by_title(pc_title)
  # 技能名とIDの対応表(ファイルから読み取り、ハッシュにする)
  f = File.open("config/skills.json")
  skills_json = f.read  # 全て読み込む
  f.close
  skills = JSON.parse(skills_json)
  # 型変換で見難いが、現在値にvalueを足した値を代入しているだけ
  ws.list[skills[skill]-2][type_abbr_to_type(type)] = 
      (ws.list[skills[skill]-2][type_abbr_to_type(type)].to_i + value.to_i).to_s
  ws.save
end

# 指定した技能の指定した種類の値一つを返す
def show_value(pc_title, skill, type)
  ws = $sp.worksheet_by_title(pc_title)
  # 技能名とIDの対応表(ファイルから読み取り、ハッシュにする)
  f = File.open("config/skills.json")
  skills_json = f.read  # 全て読み込む
  f.close
  skills = JSON.parse(skills_json)
  return ws.list[skills[skill]-2][type_abbr_to_type(type)].to_s
end

# 指定したPCの指定した技能の値(合計値)を返す
def skill_value(pc_title, skill)
  ws = $sp.worksheet_by_title(pc_title)
  # 技能名とIDの対応表(ファイルから読み取り、ハッシュにする)
  f = File.open("config/skills.json")
  skills_json = f.read  # 全て読み込む
  f.close
  skills = JSON.parse(skills_json)
  return ws.list[skills[skill]-2]["合計値"].to_i
end

# 対応表を文字列出力
def show_list
  ws = $sp.worksheet_by_title("対応表")
  msg = ""
  i = 1
  while ws[i,1] != ""
    msg = msg + i.to_s + ": " + ws[i,1] + "\n"
    i = i + 1
  end
  return msg
end

# シートの必要部分を出力
def show_sheet(name)
  ws = $sp.worksheet_by_title(name)
  msg = ""
  for i in 1..ws.num_rows
    for j in 1..ws.num_cols
      msg = msg + " \| " + ws[i,j]
    end
    msg = msg + "\n"
  end
  return msg
end