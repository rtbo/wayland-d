module output;

interface Output
{
    @property int width();
    @property int height();

    void enable();
    void disable();
}
