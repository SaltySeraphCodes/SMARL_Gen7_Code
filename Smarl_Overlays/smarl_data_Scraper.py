# Cute old script I used to get Gen3-4 Cars working with the overlay!

import math,os, time, json, mysql.connector
# this database is hosted locally (duh) cand cannot be accessed unless you come into my room directly
mydb = mysql.connector.connect(
  host="192.168.1.250",
  user="root",
  passwd="smarl_password",
  database="smarl_Data",
  unix_socket="/var/run/mysqld/mysqld.sock"
)
mycursor = mydb.cursor()
RACE_NAME = 'realtime_data'

def table_exists(table_name):
    mycursor.execute("show tables like '"+table_name+"'")
    result = mycursor.fetchone()
    if result:
        return True
    else:
        return False

def purgeZeros(raceName):
    print("Purging realtime")
    mycursor.execute("delete from "+raceName+" where pos like '0'")
    mydb.commit()


def get_name_from_tag(tag):
    conversionTable = {'GLS': "Golden Shadow", 'RTH': "Red Thunder",
                        'LMR': "Lemon Racer", 'GHP': "Grasshopper",
                        'VGD': "Vanguard", 'SHZ': "Sweet Haze",
                        'BBR': "Blue Bruiser", 'BKN': "Black Knight",
                        'CHS': 'Chaos Shifter', 'WHR': 'White Ryder' }
    return conversionTable[tag]

def get_tag_from_name(name): # Expand this list as racers get added
    conversionTable = {  "Golden Shadow": "GLS", "Red Thunder": "RTH",
                        "Lemon Racer":"LMR" , "Grasshopper": "GHP", 
                          "Vanguard": "VGD",  "Sweet Haze": "SHZ",
                       "Blue Bruiser": "BBR", "Chaos Shifter": "CHS", 
                       "Black Knight": "BKN",  "White Ryder": "WHR" }
    return conversionTable[name]

def get_name_from_color(color): # NAMes will vary depending on race qualifiers. 
    conversionTable = { '222222ff': "Golden Shadow", '7c0000ff': "Red Thunder",
                        'e2db13ff': "Lemon Racer", '0e8031ff': "Grasshopper",
                        'eeeeeeff': "White Ryder", '500aa6ff': "Sweet Haze",
                        '0a3ee2ff': "Blue Bruiser", 'ee7bf0ff': "Chaos Shifter" }
    return conversionTable[color]\


def get_color_from_name(name): # NAMes will vary depending on race qualifiers.     
    conversionTable = {  "Golden Shadow": "222222ff", "Red Thunder": "7c0000ff",
                          "Lemon Racer": "e2db13ff" , "Grasshopper": "0e8031ff", 
                          "Vanguard": "eeeeeeff",  "Sweet Haze": "500aa6ff",
                          "Blue Bruiser": "0a3ee2ff", "Chaos Shifter": "ee7bf0ff", 
                          "Black Knight": "222222ff",  "White Ryder": "eeeeeeff" }
     
    return conversionTable[name]

def get_time_from_seconds(seconds):
    minutes = "{:02.0f}".format(math.floor(seconds/60))
    seconds = "{:06.3f}".format(seconds%60)
    timeStr  = minutes + ":" +seconds
    return timeStr

def get_id_from_tag(tag): # i know its an ugly hard codded mess but it is much quicker than pulling it in from the db
    conversionTable = { 'GLS': 9, 'RTH': 5,
                        'LMR': 2, 'GHP': 4,
                        'VGD': 10, 'SHZ': 7,
                        'BBR': 6, 'BKN': 8,
                        'CHS': 3, 'WHR': 1 }
    return conversionTable[tag]

def get_tag_from_id(id):
    conversionTable = { '1': 'WHR',
                        '2': 'LMR',
                        '3': 'CHS',
                        '4': 'GHP',
                        '5': 'RTH',
                        '6': 'BBR',
                        '7': 'SHZ',
                        '8': 'BKN',
                        '9': 'GLS',
                        '10': 'VGD'}
    
    return conversionTable[str(id)]

    
def create_race_table(name):
    if table_exists(name): # and delete data = truedelet table data
        print("Resetting realtime data")
        mycursor.execute("delete from "+name)
        mydb.commit()
        return
    else:
        print("creating",name)
        mycursor.execute('''CREATE TABLE '''+name+'''
        (id int(11), name VARCHAR(255), tag VARCHAR(30) UNIQUE, color VARCHAR(100), pos SMALLINT(10),
        lapNum SMALLINT(10), lastLap VARCHAR(225), bestLap VARCHAR(255), totalTime VARCHAR(255))
        ''')

def findLogFile():
    max_mtime = 0
    max_file = ""
    for dirname,subdirs,files in os.walk("./Logs"):
        for fname in files:
            full_path = os.path.join(dirname, fname)
            mtime = os.stat(full_path).st_mtime
            if mtime > max_mtime and fname[0:4] == 'game':
                max_mtime = mtime
                max_dir = dirname
                max_file = fname
    return max_file

def checkZeros(data):
    if data['pos'] == '0': # just a hack to prevent just starting vehicles from showing
        return True
            

def readFile(logFile,raceName,mode,raceID):
    # Set the filename and open the file
    # H:\Applications\Steam\steamapps\common\Scrap Mechanic\Logs
    filename = './Logs/'+logFile
    print("opening",filename)
    file = open(filename,'r')

    #Find the size of the file and move to the end
    st_results = os.stat(filename)
    st_size = st_results[6]
    file.seek(st_size)

    while 1:
        where = file.tell()
        line = file.readline()
        if not line:
            time.sleep(1)
            file.seek(where)
        else:
            data = parseLine(line)
            if data:
                postData(raceName,data,mode,raceID)
                if data['pos'] == '0':
                    purgeZeros(RACE_NAME)
                
                    
                

def parseLine(line):
    if "smarl_data=" in line:
        startIndex = line.find("{")
        data = line[startIndex:]
        data = json.loads(data)
        racerID = data['id']
        tag = get_tag_from_id(racerID)
        name = get_name_from_tag(tag)
        color = get_color_from_name(name)
        place = str(data['place'])
        lapNum = str(data['lapNum'])
        lastLap = get_time_from_seconds(float(data['lastLap']))
        bestLap = get_time_from_seconds(float(data['bestLap']))
        totalTime = get_time_from_seconds(float(data['totalTime']))
        locationX= data['locX'] #Get float from locX
        locationY= data['locY']
        racerData = {'id': racerID, 'name': name, 'tag': tag,  'color': color, 'pos': place, 'lapNum': lapNum,
        'lastLap': lastLap, 'bestLap': bestLap, 'totalTime': totalTime, 'locX':locationX, 'locY': locationY}
        
        return racerData
    else:
        return False

def postData(raceName,racerData,mode,raceID):
    #print("racer data=",racerData) # Add SPLIT from car in front/leader
    mycursor.execute('''INSERT INTO '''+raceName+'''
                        (racerID, name, tag, color, pos, lapNum, lastLap, bestLap, totalTime, locX, locY)
                        VALUES
                        '''+
                       "('"+racerData['id']+"', '"+racerData['name']+"', '"+racerData['tag']+"', '"+racerData['color']+"',"+
                         " '"+racerData['pos']+"', '"+racerData['lapNum']+"', '"+racerData['lastLap']+"',"+
                         " '"+racerData['bestLap']+"', '"+racerData['totalTime']+"', '"+racerData['locX']+"', '"+racerData['locY']+"')"+
                         " ON DUPLICATE KEY UPDATE pos = '"+racerData['pos']+"', lapNum = '"+racerData['lapNum']+
                     "', bestLap = '"+racerData['bestLap']+"',lastLap = '"+racerData['lastLap']+"', totalTime = '"+racerData['totalTime']+"', locX = '"+racerData['locX']+"', locY = '"+racerData['locY']+"'")
    mydb.commit()
    #print(mycursor.rowcount, "records inserted or colums updated.")
    return

def main():
    raceName = 'realtime_data' # should always be realtimne_data
    raceID = 1
    mode='race'
    logFile = findLogFile()
    create_race_table(raceName)
    print("reading from",logFile)
    readFile(logFile,raceName,mode,raceID)
   
main()

