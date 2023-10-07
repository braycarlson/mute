package settings

import (
	"os"
	"path/filepath"

	"github.com/go-ini/ini"
)

type (
	Settings struct {
		Capture string
		Render  string
	}
)

func NewSettings() *Settings {
	var configuration, _ = os.UserConfigDir()
	var home = filepath.Join(configuration, "mute")
	var path = filepath.Join(home, "settings.ini")

	var err error

	err = os.MkdirAll(home, os.ModeDir)

	if err != nil {
		return &Settings{}
	}

	_, err = os.OpenFile(
		path,
		os.O_RDWR|os.O_CREATE|os.O_EXCL,
		0666,
	)

	file, _ := ini.Load(path)

	if err == nil {
		file.NewSection("capture")
		file.Section("capture").NewKey("name", "Microphone")
		// file.Section("capture").NewKey("volume", "70")

		file.NewSection("render")
		file.Section("render").NewKey("name", "Speaker")
		// file.Section("render").NewKey("volume", "30")

		err = file.SaveTo(path)
	}

	capture := file.Section("capture")
	cname := capture.Key("name").String()

	render := file.Section("render")
	rname := render.Key("name").String()

	return &Settings{
		Capture: cname,
		Render:  rname,
	}
}
