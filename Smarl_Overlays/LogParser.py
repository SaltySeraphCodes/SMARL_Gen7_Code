import os, math
import re
import json, sys
import socketio
import time
import datetime
import asyncio
#import gspread
import sharedData # NOTE these are two separate instances of same script between application.py and logParser.py
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

ALLOWED_EXTENSIONS = set(['png', 'jpg', 'jpeg', 'gif'])
sio = socketio.Client()
#gc = gspread.service_account(filename='./service_account.json')
TCP_CONNECTED = False
DUPECOUNT = 0
TOTALCARS = 0
UPLOADED_QUALI = False
UPLOADED_RACE = False
dir_path = os.path.dirname(os.path.realpath(__file__))
json_data = os.path.join(dir_path, "JsonData")
API_FILE = os.path.join(json_data, "apiInstructs.json")

#mainSheet = gc.open("Racer Data")
#resultSheet = gc.open("Race Results")
#seasonDataSheet = mainSheet.worksheet("Season "+str(sharedData._SpecificRaceData['season']))
#raceResultSheet = resultSheet.worksheet("Season "+ str(sharedData._SpecificRaceData['season']))
#print('Loaded Sheets: '+seasonDataSheet.title,raceResultSheet.title)
# Helper functions

def getAllRacerData(): # loads and parses racer Data from gspread
     data = [{}]#seasonDataSheet.get_all_records()
     print("GESPEADS EACXWE DART",data)
     sharedData._RacerData = data
     # sharedData is uselesss. write it to stupid json instead
     dataFile = open("racerData.json","w")
     json.dump(data,dataFile)
     print("wrote json")
     #print("set data",sharedData._RacerData)
     alertServerToRacerData()

def alertServerToRacerData(): # Sends all the racer data to the server
    if TCP_CONNECTED:
        print("alerting server to racerData")
        sio.emit('gotRacerData','{"hello":"world"}')
    else:
        print("skipped sending racer Data to server")
        return

def get_time_from_seconds(seconds):
    minutes = "{:02.0f}".format(math.floor(seconds/60))
    seconds = "{:06.3f}".format(seconds%60)
    timeStr  = minutes + ":" +seconds
    return timeStr

def get_seconds_from_time(time):
    minutes = time[0:2]
    seconds = time[3:5]
    milis = time[7:11]
    newTime = (int(minutes)*60) + int(seconds) + (int(milis)/1000)
    return newTime

def find_racer_by_id(id,dataList): #Finds racer according to id
    result = next((item for item in dataList if str(item["racer_id"]) == str(id)), None)
    return result

def find_finish_results_by_id(id,dataList): #Finds racer according to id
    result = next((item for item in dataList if str(item["id"]) == str(id)), None)
    #print(result)
    return result

def find_racer_by_pos(pos,dataList):
    result = next((item for item in dataList if str(item["pos"]) == str(pos)), None)
    return result


# SOCKET STUF #Async may be better?
 
@sio.event
def connect():
    global TCP_CONNECTED
    print("TCP Connected")
    TCP_CONNECTED = True

@sio.event
def connect_error():
    global TCP_CONNECTED
    print("TCP connection failed")
    TCP_CONNECTED = False
    retryConnection()

@sio.event
def disconnect():
    global TCP_CONNECTED
    print("TCP Disconnected")
    TCP_CONNECTED = False
    #retryConnection()
           
def retryConnection():
    global TCP_CONNECTED
    print("retrying connection",TCP_CONNECTED)
    try:
        sio.connect('http://localhost:5000') # Have shared data store the localhost
    except Exception as e:
        print(type(e), str(e))
        if str(e) == "Already connected":
            print('connection alive!')
            TCP_CONNECTED = True

# API Command helpers ------

def outputCommandQueue(commandQue):
    #print("OUT=>", commandQue)
    with open(API_FILE, 'w') as outfile:
        #print("opened file")
        jsonMessage = json.dumps(commandQue)
        outfile.write(jsonMessage)

def addToQue(commands):

    if not os.path.exists(API_FILE):
        f = open(API_FILE, "a") # w? instead of a?
        # make blank
        f.write('[]')
        f.close()

    with open(API_FILE, 'r') as inFile: # TODO: do a rw+ to read then write to prevent so many opens
        currentQue = json.load(inFile)

        if currentQue == None: 
            # Create empty list
            currentQue = []
            currentQue.extend(commands)
        else:
            currentQue.extend(commands)

    outputCommandQueue(currentQue)

    
def generateCommand(command,value): #Generates command dictionary
    command =  {'cmd':command, 'value':value}
    return command



# main Data=============
 

def findLogFile():
    max_mtime = 0
    max_file = ""
    for dirname,subdirs,files in os.walk("../JsonData/RaceOutput/"):
        for fname in files:
            full_path = os.path.join(dirname, fname)
            mtime = os.stat(full_path).st_mtime
            if fname == 'raceData.json':
                print("found file")
                max_mtime = mtime
                max_dir = dirname
                max_file = fname
    return max_file

def checkZeros(data):
    if data['pos'] == '0': # just a hack to prevent just starting vehicles from showing
        return True

def sortByKeys(keys,lis): #keys is a list of keys #mailny for points so reverse is true
    newList =sorted(lis, key = lambda i: (i[keys[0]], i[keys[1]], i[keys[2]], i[keys[3]], i[keys[4]]),reverse=True ) 
    return newList

def sortByKey(key,lis): #just sorts list by one key #mainly for pos so reverse is false
    newList =sorted(lis, key = lambda i: i[key] )
    return newList

def getIndexByKey(key,lis):
    #print('getting index',key,lis)
    newIndex = next((index for (index, d) in enumerate(lis) if d['ID'] == key), None)
    return newIndex
    
def getTimefromTimeStr(timeStr):
    minutes = int(timeStr[0:2])
    seconds = int(timeStr[3:5])
    milliseconds = int(timeStr[6:9])
    myTime = datetime.datetime(2019,7,12,1,minutes,seconds,milliseconds)
    return myTime

def getFastestLap_racer(finishData):
    fastestTime = None
    fastestRacer = None
    timeStr = None
    for racer in finishData:
        ch_tStr = racer['bestLap']
        chTime = getTimefromTimeStr(ch_tStr)
        if fastestTime == None:
            fastestTime = chTime
            fastestRacer = racer
            timeStr = ch_tStr
        elif chTime < fastestTime:
            fastestTime = chTime
            fastestRacer = racer
            timeStr = ch_tStr
    return timeStr,fastestRacer

def determineFastestLap(allRacers,racerLap): #checks what the fastest lap was
    racerTime = getTimefromTimeStr(racerLap)
    isFastest = True
    for racer in allRacers:
        ch_tStr = racer['bestLap']
        chTime = getTimefromTimeStr(ch_tStr)
        if chTime < racerTime:
            isFastest = False
    return isFastest

def readFile(fileName):
    data = None
    logRead = False
    numFinishPackets = 0
    dataCount = 0
    global TOTALCARS
    global UPLOADED_QUALI
    global UPLOADED_RACE
    while logRead == False:
        try:
            with open(fileName,'r') as file:
            #file = open(fileName,'r')
                data = json.load(file)
                #print('read?',sys.getsizeof(data))
                logRead = True
        except Exception as e:
            pass    
            #print("Log Read Miss",type(e), str(e)) #happens quite a bit
    if not data: # If no new data seems to be added
            #print("no data")
            logRead = True
    else: # If data is added
        # parse data here
        parsedData = None
        try:
            parsedData = parseData(data) # parses all data and returns
            outputData(parsedData)
        except Exception as e:
            print("error parsing data",e)
        
        # check for fin  
        #print('parsed',parsedData['meta_data']['lapsLeft'] ==-1,TOTALCARS,len(parsedData['realtime_data']),len(parsedData['qualifying_data']),len(parsedData['finish_data']))     
        #result = uploadRaceResults(parsedData['finish_data'])
        if parsedData:
            if parsedData['realtime_data']: # use to set number of total car
                TOTALCARS = len(parsedData['realtime_data'])
            if parsedData['meta_data']['lapsLeft'] == -1: # end lap of race
                if parsedData['finish_data'] and parsedData['meta_data']['qualifying'] == False:
                    if len(parsedData['finish_data']) == TOTALCARS and UPLOADED_RACE == False:
                        print("FInished Race, Uploading",parsedData)
                        result = uploadRaceResults(parsedData['finish_data'])
                        if result:
                            print("successfully uploaded finish data")
                            UPLOADED_RACE = True
                        else:
                            print("Uploading finish data failed",result)

                if parsedData['qualifying_data'] and parsedData['meta_data']['qualifying'] == True:
                    if len(parsedData['qualifying_data']) == TOTALCARS and UPLOADED_QUALI == False:
                        print("FInished Qualifying, Uploading") 
                        result = uploadQualResults(parsedData['qualifying_data']) #TODO: uncomment when ready
                        if result:
                            print("successfully uploaded qualifying data")
                            UPLOADED_QUALI = True
                        else:
                            print("Uploading qualifying data failed",result)
        else:
            #print('No data?')
            #dataType ='' I think this is solving extra racePackettype bug but needs to come before race packet finish
            pass

def generateResultString(data):
    output = ""
    #Sort racerdata by finish pos first
    sortedData = sortByKey('pos',data)
    for result in sortedData:
        place = str(result['id'])
        output += place +","
    output = output.strip(",")
    return output


def uploadQualResults(finishData): # same as finish but just qualifying
    race_id = sharedData._SpecificRaceData['race_id']
    track_id = sharedData._SpecificRaceData['track_id']
    timestamp = datetime.datetime.now().strftime("%m/%d/%Y %H:%M:%S") # What to do with this?
    fastestLap,fastestRacer = getFastestLap_racer(finishData)
    fastRacerName = fastestRacer['name']
    #print("Fastest lap and racer:",fastestLap,fastRacerName)
    status = sharedData.track_record_managment(track_id,fastestLap,fastestRacer)
    results = generateResultString(finishData)
    print("Got qualifying results,",results,"New Lap Record?",status)
    
    print("Uploading Qualifying results: ")
    result = sharedData.uploadQualResults(race_id,results)
    return result #TODO: Uncomment these when ready

def uploadRaceResults(finishData):
    race_id = sharedData._SpecificRaceData['race_id']
    track_id = sharedData._SpecificRaceData['track_id']
    timestamp = datetime.datetime.now().strftime("%m/%d/%Y %H:%M:%S") # What to do with this?
    fastestLap,fastestRacer = getFastestLap_racer(finishData)
    fastRacerName = fastestRacer['name']
    status = sharedData.track_record_managment(track_id,fastestLap,fastestRacer)
    results = generateResultString(finishData)
    print("Got Race results,",results,"New Lap Record?",status)
    
    print("Uploading race results: ")
    result = sharedData.uploadResults(race_id,results)
    return result

def cleanDuplicate(dataArr):
    idsIn = []
    cleanPacket = False
    # This function isn't necessary anymore

    for racer in dataArr:
        racerID = racer['id']
        if racerID not in idsIn:
            idsIn.append(racerID)
        else:
            cleanPacket = False
            #print("found Duplicate",racerID)
            i = 0
            while i <(len(dataArr)): 
                if dataArr[i]['id'] == racerID: 
                    del dataArr[i] 
                    print("deleted index",i,racerID)
                    continue
                i = i+1
        cleanPacket = True
    
    return dataArr, cleanPacket          

def generateTagFromString(string): #gets a tag from a string based on method
    removedSpaces = string.replace(" ",'')
    return removedSpaces

def getUniqueTag(name,racerData): # gets a unique tag using name based off of racer data names
    # find two tags that are the same, change one into 
    tag = generateTagFromString(name)[0:4] 
    all_tags = [] # will get populated here but pushed from parent parent parent func
    # find tag
    for index,otag in enumerate(all_tags): # generate new tag (dif method)
        if otag == tag: # need to not check self
            print("Tag conflict",tag,otag,index)
    return tag
   
def getParsedData(racerID): # gets the individual data vars, just separated out because it was ran over and over again (have all tags array get passed throw)
    
    #print('find racer',racerID,str(racerID),str(int(racerID)),sharedData._RacerData)
    formatID = str(int(racerID))
    racerData = find_racer_by_id(formatID,sharedData._RacerData)
    if racerData == None:
        #print("could not find racer",formatID, "Is League ID properly set?")
        return None,None,None,None,None,None
        # Racer is probably not in current league
    tag =  getUniqueTag(racerData['name'],racerData) #racerData['name'][0:4] # TODO: Have uniqe generation (if multi space, have one word represent from each space and thennext letter)
    name = racerData['name']
    colors = racerData['colors'].split(",")
    primary = str(colors[0])
    secondary = str(colors[1])
    tertiary = str(colors[2])
    owner = racerData['display_name'] #TODO: make difference between owner, sponsor, and logo
    return tag,name,primary,secondary,tertiary,owner

# Returns all data but parsed properly
def parseData(raw_data):
    outputData = {
        'meta_data': {},
        'qualifying_data': [],
        'finish_data': [],
        'realtime_data': []
    }
    #print('parsing data',raw_data)

    #metadata
    metaData = raw_data['md']
    status = int(metaData['status'])
    lapsLeft = metaData['lapsLeft']
    if status == 1:
        status = "Green Flag"
    elif status == 3:
        status = "Formation"
    elif status == 2:
        status = "Caution"
    elif status == 0:
        status = "Stopped"
    elif status == -1:
        status = "Qualifying"
    if metaData['qualifying'] == "true":
        qualifying = True
    else:
        qualifying = False   
    metaData = {'id': 1, 'status': status,'lapsLeft':lapsLeft,'qualifying':qualifying}
    outputData['meta_data'] = metaData 

    #realtime data
    realtimeData = raw_data['rt']
    #print("got rt data",realtimeData)
    raceData = []
    for data in (realtimeData or []):
        racerID = int(data['id'])
        tag,name,primary,secondary,tertiary,owner = getParsedData(racerID)
        
        if tag == None: # skip the ship
            #print("Skipping",racerID)
            continue
        place = int((data['place']))
        lapNum = int(data['lapNum'])
        lastLap = get_time_from_seconds(float(data['lastLap']))
        bestLap = get_time_from_seconds(float(data['bestLap']))
        timeSplit = data['timeSplit']
        locationX= data['locX'] #Get float from locX
        locationY= data['locY']
        speed = data['speed'] # calculated in driver as self.realspeed
        isFocused = data['isFocused'] # whether camera is focused on racer
        # have acccelerator and break indicator? annoying if it is only every second
        # shows color/logo? season points?
        # car Type? (how do we classify custom builds)
        #
        racerData = {'id': racerID, 'name': name, 'tag': tag,  'primary_color': primary,  'secondary_color':secondary,
                        'tertiary_color':tertiary, 'owner':owner, 'pos': place, 'lapNum': lapNum, 'speed': speed, 'isFocused': isFocused,
                        'lastLap': lastLap, 'bestLap': bestLap, 'timeSplit': timeSplit, 'locX':locationX, 'locY': locationY}
        raceData.append(racerData)
        outputData['realtime_data'] = raceData
        #print("rtDat?",outputData)
    # Qualifying Data
    qualifyingData = raw_data['qd']
    qualData = []
    for data in (qualifyingData or []):
        #print('qualdata',qualifyingData,data)
        racerID = int(data['racer_id'])
        tag,name,primary,secondary,tertiary,owner = getParsedData(racerID)
        place = int(data['position'])
        split = str(data['split'])
        bestLap = get_time_from_seconds(float(data['best_lap']))
        racerQData = {'id': racerID, 'name': name, 'tag': tag,  'primary_color': primary,  'secondary_color':secondary, 'tertiary_color': tertiary, 'owner':owner, 'pos': place, 'split': split, 'bestLap':bestLap}
        qualData.append(racerQData)
    outputData['qualifying_data'] = qualData

    # finish Data
    finishData = raw_data['fd']
    finData = []
    for data in (finishData or []):
        racerID = int(data['racer_id'])
        tag,name,primary,secondary,tertiary,owner = getParsedData(racerID)
        place = int(data['position'])
        split = str(data['split'])
        #qualPos = int(data['qualPos']) none of tis??
        bestLap = get_time_from_seconds(float(data['best_lap']))
        racerFinishData = {'id': racerID, 'name': name, 'tag': tag,  'primary_color': primary,  'secondary_color':secondary, 'tertiary_color': tertiary, 'owner':owner, 'pos': place, 'bestLap': bestLap, 'split':split}
        finData.append(racerFinishData)
    outputData['finish_data'] = finData
    
    #print('Returning parsed data',outputData)
    return outputData



def outputData(data):  #Directly output data to flask server via tcp
    size = sys.getsizeof(data)
    pass
    if not TCP_CONNECTED :
        #print("Did not send packet (not connected)")
        return 
    if size > 0:
        sio.emit('dataPacket', data) # size might be too big
        #print("Sent data packet",size)
    return size

# Readfile handler
class ReadFileHandler(FileSystemEventHandler):
    # super annoying but hard coding file finding 
    # TODO: figure out how to pass param to event handler
    fileDir = '../JsonData/RaceOutput/'
    logFile = 'raceData.json'
    fileName = fileDir+logFile
    lastDupeCount = DUPECOUNT
    def __init__(self):
        self.lastDupeCount = DUPECOUNT

    def on_modified(self, event):
        if DUPECOUNT != self.lastDupeCount: 
            #print(f'event type: {event.event_type}  path : {event.src_path}')
            # filter so only one event?
            readFile(fileName)
            self.lastDupeCount = DUPECOUNT # prevent dup


if __name__ == "__main__":
    print("starting Reader")
    sharedData.init() # pulls in proper racer data
    try:
        sio.connect('http://localhost:5056', wait_timeout = 3) # TODO: have global variable host and port
    except:
        print("connection failed, but its okay")

    logFile = findLogFile()
    fileDir = '../JsonData/RaceOutput/'
    fileName = fileDir+logFile
    print("watching",fileName)
    callback = lambda *a: readFile(fileName)
    
    event_handler = ReadFileHandler()
    observer = Observer()
    #observer.event_queue.maxsize = 1
    observer.schedule(event_handler, fileDir, recursive=False)
    observer.start()
    #print(observer.event_queue.maxsize)
    try:
        while observer.is_alive():
            DUPECOUNT += 0.1
            observer.join(0.1) # TIMEOUT DELAY ()
    finally:
        observer.stop()
        observer.join()
        
    print("stoped running")
    
# -------------------------------------------

    
    