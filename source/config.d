module config;

import logging : LogLevel;
import zconfig : Section, Desc, Short, ConfigFile, Required;

enum NoJobId = uint.max - 1;

enum Gender
{
    female,
    male
}

string toString(Gender gender) pure nothrow @safe @nogc
{
    switch (gender)
    {
    case Gender.male:
        return "남";
    case Gender.female:
    default:
        return "여";
    }
}

int toInt(Gender gender) pure nothrow @safe @nogc
{
    switch (gender)
    {
    case Gender.male:
        return 1;
    case Gender.female:
    default:
        return 0;
    }
}

enum HeadDirection
{
    straight,
    left,
    right,
    all
}

int toInt(HeadDirection headdir) pure nothrow @safe @nogc
{
    switch (headdir)
    {
    case HeadDirection.straight:
        return 0;
    case HeadDirection.right:
        return 1;
    case HeadDirection.left:
        return 2;
    default:
        return 0;
    }
}

enum MadogearType
{
    robot,
    unused,
    suit
}

int toInt(MadogearType type) pure nothrow @safe @nogc
{
    switch (type)
    {
        case MadogearType.robot:
            return 0;
        case MadogearType.unused:
            return 1;
        case MadogearType.suit:
            return 2;
        default:
            return 0;
    }
}

enum OutputFormat
{
    png,
    zip
}

int toInt(OutputFormat format) pure nothrow @safe @nogc
{
    switch (format)
    {
        case OutputFormat.png:
            return 0;
        case OutputFormat.zip:
            return 1;
        default:
            return 0;
    }
}

struct Config
{
    @ConfigFile @Short("c") @Desc("Specific config file to use instead of the default.")
    string config = "zrenderer.conf";

    @Short("o") @Desc("Output directory where all rendered sprites will be saved to.")
    string outdir = "output";

    @Desc("Path to the resource directory. All resources are tried to be found within " ~
            "this directory.")
    string resourcepath = "";

    @Short("j") @Desc("Job id(s) which should be rendered. Can contain multiple comma " ~
            "separated values as well as ranges (e.g. '1001-1999'). Providing a single value " ~
            "of 'none' will not render the body, only the head with headgers.")
    string[] job;

    @Short("g") @Desc("Gender of the player character. Possible values are: 'male' (1) or 'female' (0).")
    Gender gender = Gender.male;

    @Desc("Head id which should be used when drawing a player.")
    uint head = 1;

    @Desc("The alternative outfit for player characters. Not all characters have alternative outfits. " ~
            "In these cases the default character will be rendered instead. Value of 0 means no outfit.")
    uint outfit = 0;

    @Desc("Headgears which should be attached to the players head. Can contain up to 3 " ~
            "comma separated values.")
    uint[] headgear;

    @Desc("Garment which should be attached to the players body.")
    uint garment;

    @Desc("Weapon which should be attached to the players body.")
    uint weapon;

    @Desc("Shield which should be attached to the players body.")
    uint shield;

    @Short("a") @Desc("Action of the job which should be drawn.")
    uint action = 0;

    @Short("f") @Desc("Frame of the action which should be drawn. Set to -1 to draw all frames.")
    int frame = -1;

    @Desc("Palette for the body sprite. Set to -1 to use the standard palette.")
    int bodyPalette = -1;

    @Desc("Palette for the head sprite. Set to -1 to use the standard palette.")
    int headPalette = -1;

    @Desc("Direction in which the head should turn. This is only applied to player sprites and only to the stand " ~
            "and sit action. Possible values are: straight, left, right or all. If 'all' is set then this direction " ~
            "system is ignored and all frames are interpreted like any other one.")
    HeadDirection headdir = HeadDirection.all;

    @Desc("The alternative madogear sprite for player characters. Only applicable to madogear jobs. Possible values " ~
            "are 'robot' (0) and 'suit' (2).")
    MadogearType madogearType = MadogearType.robot;

    @Desc("Draw shadow underneath the sprite.")
    bool enableShadow = true;

    @Desc("Ignore if a class job id is a baby.")
    bool ignoreBaby = false;

    @Desc("Generate single frames of an animation.")
    bool singleframes = false;

    @Desc("If enabled the output filenames will be the checksum of input parameters. This will ensure that each " ~
            "request creates a filename that is unique to the input parameters and no overlapping for the same " ~
            "job occurs.")
    bool enableUniqueFilenames = false;

    @Desc("Whether to return already existing sprites (true) or always re-render it (false). You should only use " ~
            "this option in conjuction with 'enableUniqueFilenames=true'.")
    bool returnExistingFiles = false;

    @Desc("Sets a canvas onto which the sprite should be rendered. The canvas requires two options: its size and " ~
            "an origin point inside the canvas where the sprite should be placed. The format is as following: " ~
            "<width>x<height>±<x>±<y>. An origin point of +0+0 is equal to the top left corner. " ~
            "Example: 200x250+100+125. This would create a canvas and place the sprite in the center.")
    string canvas = "";

    @Desc("Defines the output format. Possible values are 'png' (0) or 'zip' (1). If zip is chosen the zip will contain png " ~
            "files.")
    OutputFormat outputFormat = OutputFormat.png;

    @Desc("Log level. Defines the minimum level at which logs will be shown. Possible values are: " ~
            "all, trace, info, warning, error, critical, fatal or off.")
    LogLevel loglevel = LogLevel.info;

    @Section("server")
    {
        @Desc("Hostnames of the server. Can contain multiple comma separated values.")
        string[] hosts = ["localhost"];

        @Desc("Port of the server.")
        ushort port = 11011;

        @Desc("Log file to write to. E.g. /var/log/zrenderer.log. Leaving it empty will log to stdout.")
        string logfile = "";

        @Desc("Access tokens file. File in which access tokens will be stored in. If the file does not exist it will be generated.")
        string tokenfile = "accesstokens.conf";

        @Desc("Setting this to true will add CORS headers to all responses as well as adding an additional OPTIONS route " ~
                "that returns the CORS headers.")
        bool enableCORS = false;

        @Desc("Comma separated list of origins that are allowed access through CORS. Set this to a single '*' to allow access " ~
                "from any origin. Example: https://example.com.")
        string[] allowCORSOrigin = [];

        @Desc("Whether to use TLS/SSL to secure the connection. You will also need to set the certificate and private key when " ~
                "enabling this setting. We recommend not enabling this feature but instead use a reverse proxy that handles HTTPS " ~
                "for you.")
        bool enableSSL = false;

        @Desc("Path to the certificate chain file used by TLS/SSL.")
        string certificateChainFile = "";

        @Desc("Path to the private key file used by TLS/SSL.")
        string privateKeyFile = "";
    }
}
