import os, math
from flask import Flask, render_template, url_for, g
from jinja2 import Environment, PackageLoader, select_autoescape
import requests
import json
from flask_socketio import SocketIO
import time
import asyncio
import sharedData

ALLOWED_EXTENSIONS = set(['txt', 'pdf', 'png', 'jpg', 'jpeg', 'gif'])
app = Flask(__name__)
app.config['SECRET_KEY'] = 'SUPERSECRETSKELINGTON'
socketio = SocketIO(app)
#sio = socketio.AsyncClient()
#smarl_starting_data = [] # Racer Data that gets updated after the game says so
_Racer_Data = []

#
def find_racer_by_id(id,dataList): #Finds racer according to id
    result = next((item for item in dataList if str(item["racer_id"]) == str(id)), None)
    #print(result)
    return result

# Helper functions
def get_car_data(racerID): # gets the individual data vars, just separated out because it was ran over and over again
    racerData = find_racer_by_id(str(racerID),sharedData._RacerData)
    tag = racerData['name'][0:4] # TODO: Have uniqe generation (if multi space, have one word represent from each space and thennext letter)
    name = racerData['name']
    colors = racerData['colors'].split(",")
    primary = str(colors[0])
    secondary = str(colors[1])
    tertiary = str(colors[2])
    owner = racerData['display_name'] #TODO: make difference between owner, sponsor, and logo
    return tag,name,primary,secondary,tertiary,owner


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

# Various Form classes

@app.route('/', methods=['GET','POST']) #Showsall possible overlays for quick picking
def index():
     
    return render_template('smarl_overlay_dashboard.html')
#TODO: FIGURE OUT GLOBAL STORAGE FOR FLASK TO BPUT THESE VARIABLES IN
_raceStatus = [] # Various Data that contains race status and laps left
_qualifyingData = [] # Collection of qualifying Data stored while server is up
_raceData = [] # All Race Data formatted as realtime_data, qualifying_data, finish_data, meta_data
_splitData={} #singular split
_finishData=[] # Contains information appended after a racer finishes


@socketio.on('getJson')
def handle_get_json(jsonData, methods=['GET', 'POST']):
   print("getJson?")


@socketio.on('getQual')
def handle_get_qual(jsonData, methods=['GET', 'POST']): # Grabs Qualification data (Post Qualification)
    global _qualifyingData
    #print("returning qualification Data")
    socketio.emit('qualData', _qualifyingData)

@socketio.on('getRace')
def handle_get_race(jsonData,methods=['GET','POST']):
    global _raceData
    #print("Returning Race Data",_raceData)
    socketio.emit('raceData', _raceData)

@socketio.on('getCurrentRaceData')
def handle_get_race_current_data(jsonData,methods=['GET','POST']):
    print("Returning Race Data",sharedData._SpecificRaceData)
    socketio.emit('raceData',sharedData._SpecificRaceData)


@socketio.on('getFinish')
def handle_get_finish(jsonData,methods=['GET','POST']):
    global _finishData
    #print("Returning Finish Data")
    socketio.emit('finishData',_finishData)

@socketio.on('getStatus')
def handle_get_status(jsonData,methods=['GET','POST']):
    global _raceStatus
    #print("Returning Status Data")
    #print()
    #print("STATUS!!!",_raceStatus)
    socketio.emit('statusData',_raceStatus)

@socketio.on('getSeason')
def handle_get_season(jsonData,methods=['GET','POST']):
    print("Returning Season Data",sharedData._RacerData)
    socketio.emit('seasonData',sharedData._RacerData)

@socketio.on('statusPacket')
def handle_incoming_status(jsonData, methods=['GET', 'POST']):
    print("Got status Packet")
    global _raceStatus
    _raceStatus = jsonData
    socketio.emit('statusData', jsonData)
    #print('')

@socketio.on('racePacket')
def handle_incoming_race(jsonData, methods=['GET', 'POST']):
    global _raceData
    _raceData = jsonData
    print("emit raceData",jsonData)
    socketio.emit('raceData', jsonData)
    #print('')

@socketio.on('qualPacket')
def handle_incoming_qual(jsonData, methods=['GET', 'POST']):
    global _qualifyingData
    print("Got Qual Packet")
    _qualifyingData = jsonData
    socketio.emit('qualData', jsonData)
    #print('')

@socketio.on('splitPacket')
def handle_incoming_split(jsonData, methods=['GET', 'POST']):
    global _splitData
    print("Got split Packet")
    _splitData = jsonData
    socketio.emit('splitData', jsonData)
    #print('')

@socketio.on('finishPacket')
def handle_incoming_finish(jsonData, methods=['GET', 'POST']):
    global _finishData
    print("Got Finish Packet")
    _finishData = jsonData
    socketio.emit('finishData', jsonData)
    #print('')


@socketio.on('dataPacket') # handles all universal data
def handle_incoming_data(jsonData, methods=['GET', 'POST']):
    global _raceData
    #print("Got data Packet",jsonData)
    _raceData = jsonData
    socketio.emit('raceData', jsonData)
    #print('')



@socketio.on('gotRacerData') # just to check if its there
def handle_incoming_racerData(jsonData, methods=['GET', 'POST']):
    print("Retrieving racerData") 
    jsonDataFile = open("racerData.json","r")
    print(jsonDataFile,"datafile?")
    jsonLine = json.load(jsonDataFile)
    #print(jsonLine)
    sharedData._RacerData = jsonLine
    global _Racer_Data
    _Racer_Data = jsonLine
    socketio.emit('seasonData', _Racer_Data)


# _________________________SMARL API CODE _______________________________


@app.route('/api/spawn_racer/<racer_id>')
def api_spawn_racer(racer_id, methods=['GET']):
    print("Received request to spawn racer",racer_id)
    command ={
        'cmd': 'impCAR',
        'val': str(racer_id)
    } 
    results = sharedData.addToQueue([command])
    return "Done"


@app.route('/api/remove_racer/<racer_id>')
def api_remove_racer(racer_id, methods=['GET']):
    print("Received request to Remove racer",racer_id)
    command ={
        'cmd': 'delMID',
        'val': str(racer_id)
    } 
    results = sharedData.addToQueue([command])
    return "Done"


@app.route('/api/update_tuning_data')
def api_update_tuning(methods=['GET']):
    print("Received request to Update Tuning Data")
    #results = sharedData.addToQueue([command]) if we want to do live tune changes
    sharedData.update_tuning_data()
    return "Done"

# Make sure on public facing site they can only remove racers that match their owned racers


#_______________________________ SMARL Overlay CODE _________________________________________

@app.route('/smarl_split_display', methods=['GET','POST']) # Displays Racers and the split from leader
def smarl_split_board():
    return render_template('smarl_split_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_focused_display', methods=['GET','POST']) # Displays Racers, speed, current position, and any other fun data
def smarl_focused_board():
    return render_template('smarl_focus_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_last_lap_display', methods=['GET','POST']) # Displays the last laps of all of the racers
def smarl_last_lap_board():
    return render_template('smarl_last_lap_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_best_lap_display', methods=['GET','POST']) # Displays the best laps of all of the racers
def smarl_best_lap_board():  
    return render_template('smarl_best_lap_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_qualifying_display', methods=['GET','POST']) # Displays the qualifying Split of Racers
def smarl_qualifying_board():
    return render_template('smarl_qualifying_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_status_display', methods=['GET','POST']) # Displays Laps left and Race Status
def smarl_status_board():
    return render_template('smarl_status_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_postqual_display', methods=['GET','POST']) # Displays Racers After their qualifying Session
def smarl_post_qualifying_board():
    return render_template('smarl_postQual_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_condensedqual_display', methods=['GET','POST']) # Displays Racers After their qualifying Session
def smarl_condensed_qualifying_board():
    return render_template('smarl_condensedQual_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)


@app.route('/smarl_starting_display', methods=['GET','POST'])  # Displays Racer Information Before  Race? before qualifyibng MIGERTED TOINTRODISPLAY
def smarl_starting_board():
    return render_template('smarl_starting_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_intro_display', methods=['GET','POST']) # Displays Race Information (Track, nracer...)
def smarl_intro_board():
    return render_template('smarl_intro_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_combo_display', methods=['GET','POST']) # Displays Both Last Lap and best lap... needed?
def smarl_combo_board():
    return render_template('smarl_combo_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_finish_display', methods=['GET','POST']) # Displays Race Results
def smarl_finish_board():
    return render_template('smarl_finish_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)


@app.route('/smarl_season_display', methods=['GET','POST']) # Displays Season Results using league
def smarl_season_board(): 
    # pull in new racer data
    sharedData.updateRacerData()
    print()
    print("\n")
    print("sending season data",sharedData._SpecificRaceData)
    return render_template('smarl_season_display.html',raceData=sharedData._SpecificRaceData,properties=sharedData._Properties)

@app.route('/smarl_get_realtime_data', methods=['GET','POST']) # Displays Race Results
def smarl_get_lapData(): #Get lap data
    print("REturning",_raceData)
    return json.dumps(_raceData)


@app.route('/smarl_map_display', methods=['GET','POST']) # Displays Race Results
def smarl_map_display(): #Get lap data
    print("displaying map")
    car_data = []
    map_data = []
    try: # This isnt actually necessary
        response = requests.get(sharedData.get_smarl_url() + "/get_all_racers")
        response.raise_for_status()
        car_data = response.json()
    except Exception as e:
        print("Could not get all cars",e)

    try:
        #file = open("../JsonData/TrackData/cuurent_map.json") # Use this in production
        file = open("../JsonData/TrackData/current_map.json")
        jsonData = json.load(file)
        print("Found Map data map data")
        map_data = jsonData
    except Exception as e:
        print("Could not get map data",e)


    return render_template('smarl_map_display.html',all_cars = car_data, map_data = map_data)

@app.route('/smarl_session_display', methods=['GET','POST']) # Displays Race Results
def smarl_session_display(): #Get lap data
    print("displaying session")
    return render_template('smarl_session_display.html')



@app.context_processor
def test_debug():

    def console_log(input_1,  input_2 = '', input_3 = ''):
        print("logging", input_1)
        print(input_2)
        print(input_3)
        return input_1

    return dict(log=console_log)


def main(): 
    sharedData.init()
    if '__main__' == __name__:
        socketio.run(app,host='0.0.0.0',port='5056', debug=True)
    
main()

# -------------------------------------------

    
    
